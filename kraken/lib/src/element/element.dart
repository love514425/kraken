/*
 * Copyright (C) 2019-present Alibaba Inc. All rights reserved.
 * Author: Kraken Team.
 */

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:kraken/bridge.dart';
import 'package:kraken/element.dart';
import 'package:kraken/module.dart';
import 'package:kraken/rendering.dart';
import 'package:kraken/css.dart';
import 'package:meta/meta.dart';

import '../css/flow.dart';
import 'event_handler.dart';
import 'bounding_client_rect.dart';

const String STYLE = 'style';

/// Defined by W3C Standard,
/// Most element's default width is 300 in pixel,
/// height is 150 in pixel.
const String ELEMENT_DEFAULT_WIDTH = '300px';
const String ELEMENT_DEFAULT_HEIGHT = '150px';

typedef TestElement = bool Function(Element element);

enum StickyPositionType {
  relative,
  fixed,
}

enum BoxSizeType {
  // Element which have intrinsic before layout. Such as <img /> and <video />
  intrinsic,

  // Element which have width or min-width properties defined.
  specified,

  // Element which neither have intrinsic or predefined size.
  automatic,
}

mixin ElementBase on Node {
  RenderLayoutBox _renderLayoutBox;
  RenderIntrinsic _renderIntrinsic;

  RenderBoxModel get renderBoxModel => _renderLayoutBox ?? _renderIntrinsic ?? null;
  set renderBoxModel(RenderBoxModel value) {
    if (value == null) {
      _renderIntrinsic = null;
      _renderLayoutBox = null;
    } else if (value is RenderIntrinsic) {
      _renderIntrinsic = value;
    } else if (value is RenderLayoutBox) {
      _renderLayoutBox = value;
    } else {
      if (!kReleaseMode)
        throw FlutterError('Unknown RenderBoxModel value.');
    }
  }
}

class Element extends Node
    with
        ElementBase,
        NodeLifeCycle,
        EventHandlerMixin,
        CSSTextMixin,
        CSSDecoratedBoxMixin,
        CSSSizingMixin,
        CSSFlexboxMixin,
        CSSFlowMixin,
        CSSOverflowMixin,
        CSSOpacityMixin,
        CSSTransformMixin,
        CSSVisibilityMixin,
        CSSOffsetMixin,
        CSSContentVisibilityMixin,
        CSSTransitionMixin,
        CSSFilterEffectsMixin {
  Map<String, dynamic> properties;
  List<String> events;

  /// Should create repaintBoundary for this element to repaint separately from parent.
  bool repaintSelf;

  bool shouldBlockStretch = true;

  // Position of sticky element changes between relative and fixed of scroll container
  StickyPositionType stickyStatus = StickyPositionType.relative;
  // Original offset to scroll container of sticky element
  Offset originalScrollContainerOffset;
  // Original offset of sticky element
  Offset originalOffset;

  final String tagName;

  final Map<String, dynamic> defaultStyle;

  /// The default display type of
  String defaultDisplay;

  // After `this` created, useful to set default properties, override this for individual element.
  void afterConstruct() {}

  // Style declaration from user.
  CSSStyleDeclaration style;

  RenderDecoratedBox stickyPlaceholder;
  // Placeholder renderObject of positioned element(absolute/fixed)
  // used to get original coordinate before move away from document flow
  RenderObject renderPositionedPlaceholder;

  bool get isValidSticky {
    return style[POSITION] == STICKY && (style.contains(TOP) || style.contains(BOTTOM));
  }

  Element(
    int targetId,
    ElementManager elementManager, {
    this.tagName,
    this.defaultStyle = const {},
    this.events = const [],
    // Whether element allows children.
    bool isIntrinsicBox = false,
    this.repaintSelf = false
  }) : assert(targetId != null),
        assert(tagName != null),
        super(NodeType.ELEMENT_NODE, targetId, elementManager, tagName) {
    if (properties == null) properties = {};
    if (events == null) events = [];

    defaultDisplay = defaultStyle.containsKey(DISPLAY) ? defaultStyle[DISPLAY] : BLOCK;
    _isIntrinsicBox = isIntrinsicBox;

    style = CSSStyleDeclaration(this);
    initializeRenderObject();
    style.addStyleChangeListener(_onStyleChanged);

    _setDefaultStyle();
  }

  bool _isIntrinsicBox = false;
  bool _initialized = false;

  @override
  void initializeRenderObject() {
    if (_initialized) {
      return;
    }
    // Content children layout, BoxModel content.
    if (_isIntrinsicBox) {
      _renderIntrinsic = _createRenderIntrinsic(this, repaintSelf: repaintSelf);
    } else {
      _renderLayoutBox = createRenderLayout(this, repaintSelf: repaintSelf);
      childNodes.forEach((Node child) {
        child.attachTo(this);
      });
    }
    _initialized = true;
  }

  void _setDefaultStyle() {
    if (defaultStyle != null && defaultStyle.isNotEmpty) {
      defaultStyle.forEach((property, dynamic value) {
        style.setProperty(property, value);
      });
    }
  }

  void _scrollListener(double scrollOffset, AxisDirection axisDirection) {
    layoutStickyChildren(scrollOffset, axisDirection);
  }

  // Set sticky child offset according to scroll offset and direction
  void layoutStickyChild(Element child, double scrollOffset, AxisDirection axisDirection) {
    CSSStyleDeclaration childStyle = child.style;
    bool isFixed = false;
    RenderBox childRenderBoxModel = child.renderBoxModel;

    if (child.originalScrollContainerOffset == null) {
      Offset horizontalScrollContainerOffset =
          childRenderBoxModel.localToGlobal(Offset.zero, ancestor: child.elementManager.getRootRenderObject())
              - renderBoxModel.localToGlobal(Offset.zero, ancestor: child.elementManager.getRootRenderObject());
      Offset verticalScrollContainerOffset =
          childRenderBoxModel.localToGlobal(Offset.zero, ancestor: child.elementManager.getRootRenderObject())
              - renderBoxModel.localToGlobal(Offset.zero, ancestor: child.elementManager.getRootRenderObject());

      double offsetY = verticalScrollContainerOffset.dy;
      double offsetX = horizontalScrollContainerOffset.dx;
      if (axisDirection == AxisDirection.down) {
        offsetY += scrollOffset;
      } else if (axisDirection == AxisDirection.right) {
        offsetX += scrollOffset;
      }
      // Save original offset to scroll container in element tree to
      // act as base offset to compute dynamic sticky offset later
      child.originalScrollContainerOffset = Offset(offsetX, offsetY);
    }

    // Sticky offset to scroll container must include padding
    EdgeInsetsGeometry padding = _renderLayoutBox.padding;
    EdgeInsets resolvedPadding = EdgeInsets.all(0);
    if (padding != null) {
      resolvedPadding = padding.resolve(TextDirection.ltr);
    }

    RenderLayoutParentData boxParentData = childRenderBoxModel?.parentData;

    if (child.originalOffset == null) {
      child.originalOffset = boxParentData.offset;
    }

    double offsetY = child.originalOffset.dy;
    double offsetX = child.originalOffset.dx;

    double childHeight = childRenderBoxModel?.size?.height;
    double childWidth = childRenderBoxModel?.size?.width;
    // Sticky element cannot exceed the boundary of its parent element container
    RenderBox parentContainer = child.parent._renderLayoutBox;
    double minOffsetY = 0;
    double maxOffsetY = parentContainer.size.height - childHeight;
    double minOffsetX = 0;
    double maxOffsetX = parentContainer.size.width - childWidth;

    if (axisDirection == AxisDirection.down) {
      double offsetTop = child.originalScrollContainerOffset.dy - scrollOffset;
      double viewPortHeight = renderBoxModel?.size?.height;
      double offsetBottom = viewPortHeight - childHeight - offsetTop;

      if (childStyle.contains(TOP)) {
        double top = CSSLength.toDisplayPortValue(childStyle[TOP]) + resolvedPadding.top;
        isFixed = offsetTop < top;
        if (isFixed) {
          offsetY += top - offsetTop;
          if (offsetY > maxOffsetY) {
            offsetY = maxOffsetY;
          }
        }
      } else if (childStyle.contains(BOTTOM)) {
        double bottom = CSSLength.toDisplayPortValue(childStyle[BOTTOM]) + resolvedPadding.bottom;
        isFixed = offsetBottom < bottom;
        if (isFixed) {
          offsetY += offsetBottom - bottom;
          if (offsetY < minOffsetY) {
            offsetY = minOffsetY;
          }
        }
      }

      if (isFixed) {
        boxParentData.offset = Offset(
          boxParentData.offset.dx,
          offsetY,
        );
      } else {
        boxParentData.offset = Offset(
          boxParentData.offset.dx,
          child.originalOffset.dy,
        );
      }
    } else if (axisDirection == AxisDirection.right) {
      double offsetLeft = child.originalScrollContainerOffset.dx - scrollOffset;
      double viewPortWidth = renderBoxModel?.size?.width;
      double offsetRight = viewPortWidth - childWidth - offsetLeft;

      if (childStyle.contains(LEFT)) {
        double left = CSSLength.toDisplayPortValue(childStyle[LEFT]) + resolvedPadding.left;
        isFixed = offsetLeft < left;
        if (isFixed) {
          offsetX += left - offsetLeft;
          if (offsetX > maxOffsetX) {
            offsetX = maxOffsetX;
          }
        }
      } else if (childStyle.contains(RIGHT)) {
        double right = CSSLength.toDisplayPortValue(childStyle[RIGHT]) + resolvedPadding.right;
        isFixed = offsetRight < right;
        if (isFixed) {
          offsetX += offsetRight - right;
          if (offsetX < minOffsetX) {
            offsetX = minOffsetX;
          }
        }
      }

      if (isFixed) {
        boxParentData.offset = Offset(
          offsetX,
          boxParentData.offset.dy,
        );
      } else {
        boxParentData.offset = Offset(
          child.originalOffset.dx,
          boxParentData.offset.dy,
        );
      }
    }

    if (isFixed) {
      // Change sticky status to fixed
      child.stickyStatus = StickyPositionType.fixed;
      boxParentData.isOffsetSet = true;
      childRenderBoxModel.markNeedsPaint();
    } else {
      // Change sticky status to relative
      if (child.stickyStatus == StickyPositionType.fixed) {
        child.stickyStatus = StickyPositionType.relative;
        // Reset child offset to its original offset
        childRenderBoxModel.markNeedsPaint();
      }
    }
  }

  // Calculate sticky status according to scroll offset and scroll direction
  void layoutStickyChildren(double scrollOffset, AxisDirection axisDirection) {
    List<Element> stickyElements = _findStickyChildren(this);
    stickyElements.forEach((Element el) {
      layoutStickyChild(el, scrollOffset, axisDirection);
    });
  }

  void _updatePosition(CSSPositionType prevPosition, CSSPositionType currentPosition) {
    if (renderBoxModel.parentData is RenderLayoutParentData) {
      (renderBoxModel.parentData as RenderLayoutParentData).position = currentPosition;
    }
    // Move element according to position when it's already connected
    if (isConnected) {
      if (currentPosition == CSSPositionType.static) {
        // Loop renderObject children to move positioned children to its containing block
        _renderLayoutBox.visitChildren((childRenderObject) {
          if (childRenderObject is RenderBoxModel) {
            Element child = elementManager.getEventTargetByTargetId<Element>(childRenderObject.targetId);
            CSSPositionType childPositionType = CSSPositionedLayout.parsePositionType(child.style[POSITION]);
            if (childPositionType == CSSPositionType.absolute || childPositionType == CSSPositionType.fixed) {
              Element containgBlockElement = _findContainingBlock(child);
              child.detach();
              child.attachTo(containgBlockElement);
            }
          }
        });

        // Move self from containing block to original position in element tree
        if (prevPosition == CSSPositionType.absolute || prevPosition == CSSPositionType.fixed) {
          RenderPositionHolder renderPositionHolder = renderBoxModel.renderPositionHolder;
          if (renderPositionHolder != null) {
            RenderLayoutBox parentLayoutBox = renderPositionHolder.parent;
            int parentTargetId = parentLayoutBox.targetId;
            Element parentElement = elementManager.getEventTargetByTargetId<Element>(parentTargetId);

            List<RenderObject> layoutChildren = [];
            parentLayoutBox.visitChildren((child) {
              layoutChildren.add(child);
            });
            int idx = layoutChildren.indexOf(renderPositionHolder);
            RenderObject previousSibling;
            if (idx > 0) {
              /// RenderBoxModel and its placeholder is the same
              if (layoutChildren[idx - 1] == renderBoxModel) {
                /// Placeholder is placed after its original renderBoxModel
                /// get idx - 2 as its previous sibling
                previousSibling = idx > 1 ? layoutChildren[idx - 2] : null;
              } else { /// RenderBoxModel and its placeholder is different
                previousSibling = layoutChildren[idx - 1];
              }
            } else {
              previousSibling = null;
            }
            detach();
            attachTo(parentElement, after: previousSibling);
          }
        }

        // Reset stick element offset to normal flow
        if (prevPosition == CSSPositionType.sticky) {
          RenderLayoutParentData boxParentData = renderBoxModel?.parentData;
          boxParentData.isOffsetSet = false;
          renderBoxModel.markNeedsLayout();
          renderBoxModel.markNeedsPaint();
        }
      } else {
        // Move self to containing block
        if (currentPosition == CSSPositionType.absolute || currentPosition == CSSPositionType.fixed) {
          Element containgBlockElement = _findContainingBlock(this);
          detach();
          attachTo(containgBlockElement);
        }

        // Loop children tree to find and append positioned children whose containing block is self
        List<Element> positionedChildren = [];
        _findPositionedChildren(this, positionedChildren);
        positionedChildren.forEach((child) {
          child.detach();
          child.attachTo(this);
        });

        // Set stick element offset
        if (currentPosition == CSSPositionType.sticky) {
          Element scrollContainer = _findScrollContainer(this);
          // Set sticky child offset manually
          scrollContainer.layoutStickyChild(this, 0, AxisDirection.down);
          scrollContainer.layoutStickyChild(this, 0, AxisDirection.right);
        }
      }
    }
  }

  void _findPositionedChildren(Element parent, List<Element> positionedChildren) {
    for (int i = 0; i < parent.children.length; i++) {
      Element child = parent.children[i];
      CSSPositionType childPositionType = CSSPositionedLayout.parsePositionType(child.style[POSITION]);
      if (childPositionType == CSSPositionType.absolute || childPositionType == CSSPositionType.fixed) {
        positionedChildren.add(child);
      } else if (child.children.length != 0) {
        _findPositionedChildren(child, positionedChildren);
      }
    }
  }

  Element getElementById(Element parentElement, int targetId) {
    Element result = null;
    List childNodes = parentElement.childNodes;

    for (int i = 0; i < childNodes.length; i++) {
      Element element = childNodes[i];
      if (element.targetId == targetId) {
        result = element;
        break;
      }
    }
    return result;
  }

  void addChild(RenderObject child) {
    if (_renderLayoutBox != null) {
      _renderLayoutBox.add(child);
    } else {
      _renderIntrinsic.child = child;
    }
  }

  @override
  void dispose() {
    assert(renderBoxModel != null);
    assert(renderBoxModel.parent == null);

    renderBoxModel = null;
    _initialized = false;
  }

  @override
  bool get attached => renderBoxModel != null && renderBoxModel.attached;

  // Attach renderObject of current node to parent
  @override
  void attachTo(Element parent, {RenderObject after}) {
    if (!_initialized) {
      initializeRenderObject();
    }

    CSSStyleDeclaration parentStyle = parent.style;
    CSSDisplay parentDisplayValue =
       CSSSizing.getDisplay(CSSStyleDeclaration.isNullOrEmptyValue(parentStyle[DISPLAY]) ? parent.defaultDisplay : parentStyle[DISPLAY]);
    // InlineFlex or Flex
    bool isParentFlexDisplayType = parentDisplayValue == CSSDisplay.flex || parentDisplayValue == CSSDisplay.inlineFlex;

    CSSPositionType positionType = CSSPositionedLayout.parsePositionType(style[POSITION]);
    switch (positionType) {
      case CSSPositionType.absolute:
      case CSSPositionType.fixed:
        parent._addPositionedChild(this, positionType);
        parent._renderLayoutBox.markNeedsSortChildren();
        break;
      case CSSPositionType.sticky:
        parent._addStickyChild(this, after);
        parent._renderLayoutBox.markNeedsSortChildren();
        break;
      case CSSPositionType.relative:
      case CSSPositionType.static:
        parent._renderLayoutBox.insert(renderBoxModel, after: after);
        break;
    }

    /// Update flex siblings.
    if (isParentFlexDisplayType) parent.children.forEach(_updateFlexItemStyle);
  }

  // Detach renderObject of current node from parent
  @override
  void detach() {
    RenderPositionHolder renderPositionHolder = renderBoxModel.renderPositionHolder;
    // Remove placeholder of positioned element
    if (renderPositionHolder != null) {
      ContainerRenderObjectMixin parent = renderPositionHolder.parent;
      if (parent != null) {
        parent.remove(renderPositionHolder);
      }
    }
    (renderBoxModel.parent as ContainerRenderObjectMixin).remove(renderBoxModel);

    childNodes.forEach((child) {
      child.detach();
    });
    dispose();
  }

  @override
  @mustCallSuper
  Node appendChild(Node child) {
    super.appendChild(child);

    VoidCallback doAppendChild = () {
      // Only append node types which is visible in RenderObject tree
      if (child is NodeLifeCycle) {
        _append(child, after: _renderLayoutBox.lastChild);
        child.fireAfterConnected();
      }
    };

    if (isConnected) {
      doAppendChild();
    } else {
      queueAfterConnected(doAppendChild);
    }

    return child;
  }

  @override
  @mustCallSuper
  Node removeChild(Node child) {
    // Not remove node type which is not present in RenderObject tree such as Comment
    // Only append node types which is visible in RenderObject tree
    // Only remove childNode when it has parent
    if (child is NodeLifeCycle && child.attached) {
      child.detach();
    }

    super.removeChild(child);
    return child;
  }

  @override
  @mustCallSuper
  Node insertBefore(Node child, Node referenceNode) {
    int referenceIndex = childNodes.indexOf(referenceNode);

    // Node.insertBefore will change element tree structure,
    // so get the referenceIndex before calling it.
    Node node = super.insertBefore(child, referenceNode);
    VoidCallback doInsertBefore = () {
      if (referenceIndex != -1) {
        Node after;
        RenderObject afterRenderObject;
        if (referenceIndex == 0) {
          after = null;
        } else {
          do {
            after = childNodes[--referenceIndex];
          } while (after is! Element && referenceIndex > 0);
          if (after is Element) {
            afterRenderObject = after?.renderBoxModel;
          }
        }
        _append(child, after: afterRenderObject);
        if (child is NodeLifeCycle) child.fireAfterConnected();
      }
    };

    if (isConnected) {
      doInsertBefore();
    } else {
      queueAfterConnected(doInsertBefore);
    }
    return node;
  }

  // Add placeholder to positioned element for calculate original
  // coordinate before moved away
  void addPositionPlaceholder() {
    if (renderPositionedPlaceholder == null || !renderPositionedPlaceholder.attached) {
      addChild(renderPositionedPlaceholder);
    }
  }

  void _addPositionedChild(Element child, CSSPositionType position) {
    // RenderPosition parentRenderPosition;
    RenderLayoutBox parentRenderLayoutBox;

    switch (position) {
      case CSSPositionType.absolute:
        Element containingBlockElement = _findContainingBlock(child);
        parentRenderLayoutBox = containingBlockElement._renderLayoutBox;
        break;

      case CSSPositionType.fixed:
        final Element rootEl = elementManager.getRootElement();
        parentRenderLayoutBox = rootEl._renderLayoutBox;
        break;

      case CSSPositionType.sticky:
        Element containingBlockElement = _findContainingBlock(child);
        parentRenderLayoutBox = containingBlockElement._renderLayoutBox;
        break;

      default:
        return;
    }
    Size preferredSize = Size.zero;
    CSSDisplay childDisplay = CSSSizing.getDisplay(child.style[DISPLAY]);
    if (childDisplay != CSSDisplay.inline || (position != CSSPositionType.static)) {
      preferredSize = Size(
        CSSLength.toDisplayPortValue(child.style[WIDTH]) ?? 0,
        CSSLength.toDisplayPortValue(child.style[HEIGHT]) ?? 0,
      );
    }

    RenderPositionHolder childPositionHolder = RenderPositionHolder(preferredSize: preferredSize);

    RenderBoxModel childRenderBoxModel = child.renderBoxModel;
    childRenderBoxModel.renderPositionHolder = childPositionHolder;
    _setPositionedChildParentData(parentRenderLayoutBox, child);
    childPositionHolder.realDisplayedBox = childRenderBoxModel;

    parentRenderLayoutBox.add(childRenderBoxModel);
    /// Placeholder of flexbox needs to inherit size from its real display box,
    /// so it needs to layout after real box layout
    child.parent.addChild(childPositionHolder);
  }

  void _addStickyChild(Element child, RenderObject after) {
    RenderBoxModel childRenderBoxModel = child.renderBoxModel;
    // Only layout box can have sticky child.
    assert(childRenderBoxModel is RenderLayoutBox);
    (renderBoxModel as RenderLayoutBox).insert(childRenderBoxModel, after: after);

    // Set sticky element offset
    Element scrollContainer = _findScrollContainer(child);
    // Flush layout first to calculate sticky offset
    if (!childRenderBoxModel.hasSize) {
      childRenderBoxModel.owner.flushLayout();
    }
    // Set sticky child offset manually
    scrollContainer.layoutStickyChild(child, 0, AxisDirection.down);
    scrollContainer.layoutStickyChild(child, 0, AxisDirection.right);
  }

  // Inline box including inline/inline-block/inline-flex/...
  bool get isInlineBox {
    String displayValue = style[DISPLAY];
    return displayValue.startsWith(INLINE);
  }

  // Inline content means children should be inline elements.
  bool get isInlineContent {
    String displayValue = style[DISPLAY];
    return displayValue == INLINE;
  }

  /// Append a child to childList, if after is null, insert into first.
  void _append(Node child, {RenderBox after}) {
    // @NOTE: Make sure inline-box only have inline children, or print warning.
    if ((child is Element) && !child.isInlineBox) {
      if (isInlineContent) print('[WARN]: Can not nest non-inline element into non-inline parent element.');
    }

    // Only append childNode when it is not attached.
    if (!child.attached) child.attachTo(this, after: after);
  }

  void _updateFlexItemStyle(Element element) {
    ParentData childParentData = element.renderBoxModel.parentData;
    if (childParentData is RenderFlexParentData) {
      final RenderFlexParentData parentData = childParentData;
      RenderFlexParentData flexParentData = CSSFlex.getParentData(element.style);
      parentData.flexGrow = flexParentData.flexGrow;
      parentData.flexShrink = flexParentData.flexShrink;
      parentData.flexBasis = flexParentData.flexBasis;
      parentData.alignSelf = flexParentData.alignSelf;

      element.renderBoxModel.markNeedsLayout();
    }
  }

  void _onStyleChanged(String property, String original, String present, bool inAnimation) {
    switch (property) {
      case DISPLAY:
        _styleDisplayChangedListener(property, original, present);
        break;

      case POSITION:
      case Z_INDEX:
        _stylePositionChangedListener(property, original, present);
        break;

      case TOP:
      case LEFT:
      case BOTTOM:
      case RIGHT:
        _styleOffsetChangedListener(property, original, present);
        break;

      case FLEX_DIRECTION:
      case FLEX_WRAP:
      case ALIGN_SELF:
      case ALIGN_CONTENT:
      case ALIGN_ITEMS:
      case JUSTIFY_CONTENT:
        _styleFlexChangedListener(property, original, present);
        break;

      case FLEX_GROW:
      case FLEX_SHRINK:
      case FLEX_BASIS:
        _styleFlexItemChangedListener(property, original, present);
        break;

      case SLIVER_DIRECTION:
        _styleSliverDirectionChangedListener(property, original, present);
        break;

      case TEXT_ALIGN:
        _styleTextAlignChangedListener(property, original, present);
        break;

      case PADDING_TOP:
      case PADDING_RIGHT:
      case PADDING_BOTTOM:
      case PADDING_LEFT:
        _stylePaddingChangedListener(property, original, present);
        break;

      case WIDTH:
      case MIN_WIDTH:
      case MAX_WIDTH:
      case HEIGHT:
      case MIN_HEIGHT:
      case MAX_HEIGHT:
        _styleSizeChangedListener(property, original, present);
        break;

      case OVERFLOW_X:
      case OVERFLOW_Y:
        _styleOverflowChangedListener(property, original, present);
        break;

      case BACKGROUND_COLOR:
      case BACKGROUND_ATTACHMENT:
      case BACKGROUND_IMAGE:
      case BACKGROUND_REPEAT:
      case BACKGROUND_POSITION:
      case BACKGROUND_SIZE:
      case BACKGROUND_CLIP:
      case BACKGROUND_ORIGIN:
      case BORDER_LEFT_WIDTH:
      case BORDER_TOP_WIDTH:
      case BORDER_RIGHT_WIDTH:
      case BORDER_BOTTOM_WIDTH:
      case BORDER_TOP_LEFT_RADIUS:
      case BORDER_TOP_RIGHT_RADIUS:
      case BORDER_BOTTOM_LEFT_RADIUS:
      case BORDER_BOTTOM_RIGHT_RADIUS:
      case BORDER_LEFT_STYLE:
      case BORDER_TOP_STYLE:
      case BORDER_RIGHT_STYLE:
      case BORDER_BOTTOM_STYLE:
      case BORDER_LEFT_COLOR:
      case BORDER_TOP_COLOR:
      case BORDER_RIGHT_COLOR:
      case BORDER_BOTTOM_COLOR:
      case BOX_SHADOW:
        _styleBoxChangedListener(property, original, present);
        break;

      case MARGIN_LEFT:
      case MARGIN_TOP:
      case MARGIN_RIGHT:
      case MARGIN_BOTTOM:
        _styleMarginChangedListener(property, original, present);
        break;

      case OPACITY:
        _styleOpacityChangedListener(property, original, present);
        break;
      case VISIBILITY:
        _styleVisibilityChangedListener(property, original, present);
        break;
      case CONTENT_VISIBILITY:
        _styleContentVisibilityChangedListener(property, original, present);
        break;
      case TRANSFORM:
        _styleTransformChangedListener(property, original, present);
        break;
      case TRANSFORM_ORIGIN:
        _styleTransformOriginChangedListener(property, original, present);
        break;
      case TRANSITION_DELAY:
      case TRANSITION_DURATION:
      case TRANSITION_TIMING_FUNCTION:
      case TRANSITION_PROPERTY:
        _styleTransitionChangedListener(property, original, present);
        break;

      case FILTER:
        _styleFilterChangedListener(property, original, present);
        break;
    }

    // Text Style
    switch(property) {
      case COLOR:
        _updateTextChildNodesStyle();
        // Color change should trigger currentColor update
        _styleBoxChangedListener(property, original, present);
        break;
      case OVERFLOW_X:
      case OVERFLOW_Y:
      case TEXT_SHADOW:
      case TEXT_DECORATION_LINE:
      case TEXT_DECORATION_STYLE:
      case FONT_WEIGHT:
      case FONT_STYLE:
      case FONT_SIZE:
      case LETTER_SPACING:
      case WORD_SPACING:
        _updateTextChildNodesStyle();
        break;
    }
  }

  void _styleDisplayChangedListener(String property, String original, String present) {
    // Display change may case width/height doesn't works at all.
    _styleSizeChangedListener(property, original, present);

    CSSDisplay originalDisplay = CSSSizing.getDisplay(CSSStyleDeclaration.isNullOrEmptyValue(original) ? defaultDisplay : original);
    CSSDisplay presentDisplay = CSSSizing.getDisplay(CSSStyleDeclaration.isNullOrEmptyValue(present) ? defaultDisplay : present);

    renderBoxModel.display = presentDisplay;

    if (originalDisplay != presentDisplay && renderBoxModel is RenderLayoutBox) {
      RenderLayoutBox prevRenderLayoutBox = renderBoxModel;
      bool shouldReattach = parent != null;
      renderBoxModel = createRenderLayout(this, prevRenderLayoutBox: prevRenderLayoutBox, repaintSelf: repaintSelf);

      if (shouldReattach && prevRenderLayoutBox != renderBoxModel) {
        RenderLayoutBox parentRenderObject = parent.renderBoxModel;
        RenderBoxModel previous = previousSibling is Element ? (previousSibling as Element).renderBoxModel : null;
        parentRenderObject.remove(prevRenderLayoutBox);
        parentRenderObject.insert(renderBoxModel, after: previous);
      } else {
        renderBoxModel.markNeedsLayout();
      }
    }
  }

  void _stylePositionChangedListener(String property, String original, String present) {
    /// Update position.
    CSSPositionType prevPosition = CSSPositionedLayout.parsePositionType(original);
    CSSPositionType currentPosition = CSSPositionedLayout.parsePositionType(present);

    // Position changed.
    if (prevPosition != currentPosition) {
      _updatePosition(prevPosition, currentPosition);
    }
  }

  void _styleOffsetChangedListener(String property, String original, String present) {
    updateRenderOffset(renderBoxModel, property, present);
  }

  void _styleTextAlignChangedListener(String property, String original, String present) {
    _updateDecorationRenderLayoutBox();
  }

  void _updateDecorationRenderLayoutBox() {
    if (renderBoxModel is RenderFlexLayout) {
      CSSFlexboxMixin.decorateRenderFlex(renderBoxModel, style);
    } else if (renderBoxModel is RenderFlowLayout) {
      CSSFlowMixin.decorateRenderFlow(renderBoxModel, style);
    }
  }

  void _styleFilterChangedListener(String property, String original, String present) {
    updateFilterEffects(renderBoxModel, present);
  }

  void _styleTransitionChangedListener(String property, String original, String present) {
    if (present != null) updateTransition(style);
  }

  void _styleOverflowChangedListener(String property, String original, String present) {
    updateRenderOverflow(renderBoxModel, this, _scrollListener);
  }

  void _stylePaddingChangedListener(String property, String original, String present) {
    updateRenderPadding(renderBoxModel, style, property, present);
  }

  void _styleSizeChangedListener(String property, String original, String present) {
    updateRenderSizing(renderBoxModel, style, property, present);

    if (property == WIDTH || property == HEIGHT) {
      updateRenderOffset(renderBoxModel, property, present);
    }
  }

  void _styleMarginChangedListener(String property, String original, String present) {
    updateRenderMargin(renderBoxModel, style, property, present);
  }

  void _styleFlexChangedListener(String property, String original, String present) {
    _updateDecorationRenderLayoutBox();
  }

  void _styleFlexItemChangedListener(String property, String original, String present) {
    CSSDisplay display = CSSSizing.getDisplay(CSSStyleDeclaration.isNullOrEmptyValue(style[DISPLAY]) ? defaultDisplay : style[DISPLAY]);
    if (display == CSSDisplay.flex || display == CSSDisplay.inlineFlex) {
      children.forEach((Element child) {
        _updateFlexItemStyle(child);
      });
    }
  }

  void _styleSliverDirectionChangedListener(String property, String original, String present) {
    CSSDisplay display = CSSSizing.getDisplay(CSSStyleDeclaration.isNullOrEmptyValue(style[DISPLAY]) ? defaultDisplay : style[DISPLAY]);
    if (display == CSSDisplay.sliver) {
      assert(renderBoxModel is RenderRecyclerLayout);
      RenderRecyclerLayout renderRecyclerLayout = renderBoxModel;
      renderRecyclerLayout.axis = RenderRecyclerLayout.resolveAxis(style);
    }
  }

  void _styleBoxChangedListener(String property, String original, String present) {
    updateRenderDecoratedBox(renderBoxModel, style, property, original, present);
  }

  void _styleOpacityChangedListener(String property, String original, String present) {
    // Update opacity.
    updateRenderOpacity(renderBoxModel, this, present);
  }

  void _styleVisibilityChangedListener(String property, String original, String present) {
    // Update visibility
    updateRenderVisibility(CSSVisibilityMixin.getVisibility(present));
  }

  void _styleContentVisibilityChangedListener(String property, original, present) {
    // Update content visibility.
    updateRenderContentVisibility(CSSContentVisibilityMixin.getContentVisibility(present));
  }

  void _styleTransformChangedListener(String property, String original, String present) {
    // Update transform.
    updateRenderTransform(this, renderBoxModel, present);
  }

  void _styleTransformOriginChangedListener(String property, String original, String present) {
    // Update transform.
    updateRenderTransformOrigin(renderBoxModel, present);
  }

  // Update textNode style when container style changed
  void _updateTextChildNodesStyle() {
    childNodes.forEach((node) {
      if (node is TextNode) node.updateTextStyle();
    });
  }

  // Universal style property change callback.
  @mustCallSuper
  void setStyle(String key, value) {
    // @HACK: delay transition property at next frame to make sure transition trigger after all style had been set.
    // https://github.com/WebKit/webkit/blob/master/Source/WebCore/style/StyleTreeResolver.cpp#L220
    // This it not a good solution between webkit's implementation which write all new style property into an RenderStyle object
    // then trigger the animation phase.
    if (key == TRANSITION) {
      SchedulerBinding.instance.addPostFrameCallback((timestamp) {
        style.setProperty(key, value);
      });
      return;
    } else {
      // @NOTE: See [CSSStyleDeclaration.setProperty], value change will trigger
      // [StyleChangeListener] to be invoked in sync.
      style.setProperty(key, value);
    }
  }

  @mustCallSuper
  void setProperty(String key, value) {
    // Each key change will emit to `setStyle`
    if (key == STYLE) {
      assert(value is Map<String, dynamic>);
      // @TODO: Consider `{ color: red }` to `{}`, need to remove invisible keys.
      (value as Map<String, dynamic>).forEach(setStyle);
    } else {
      switch(key) {
        case 'scrollTop':
          // need to flush layout to get correct size
          elementManager.getRootRenderObject().owner.flushLayout();
          setScrollTop(value.toDouble());
          break;
        case 'scrollLeft':
          // need to flush layout to get correct size
          elementManager.getRootRenderObject().owner.flushLayout();
          setScrollLeft(value.toDouble());
          break;
      }
      properties[key] = value;
    }
  }

  @mustCallSuper
  dynamic getProperty(String key) {
    switch(key) {
      case 'offsetTop':
        // need to flush layout to get correct size
        elementManager.getRootRenderObject().owner.flushLayout();
        return getOffsetY();
      case 'offsetLeft':
        // need to flush layout to get correct size
        elementManager.getRootRenderObject().owner.flushLayout();
        return getOffsetX();
      case 'offsetWidth':
        // need to flush layout to get correct size
        elementManager.getRootRenderObject().owner.flushLayout();
        return renderBoxModel.hasSize ? renderBoxModel.size.width : 0;
      case 'offsetHeight':
        // need to flush layout to get correct size
        elementManager.getRootRenderObject().owner.flushLayout();
        return renderBoxModel.hasSize ? renderBoxModel.size.height : 0;
        // @TODO support clientWidth clientHeight clientLeft clientTop
      case 'clientWidth':
        // need to flush layout to get correct size
        elementManager.getRootRenderObject().owner.flushLayout();
        return renderBoxModel.clientWidth;
      case 'clientHeight':
        // need to flush layout to get correct size
        elementManager.getRootRenderObject().owner.flushLayout();
        return renderBoxModel.clientHeight;
      case 'clientLeft':
        // need to flush layout to get correct size
        elementManager.getRootRenderObject().owner.flushLayout();
        return renderBoxModel.borderLeft;
        break;
      case 'clientTop':
        // need to flush layout to get correct size
        elementManager.getRootRenderObject().owner.flushLayout();
        return renderBoxModel.borderTop;
        break;
      case 'scrollTop':
        return getScrollTop();
      case 'scrollLeft':
        return getScrollLeft();
      case 'scrollHeight':
        return getScrollHeight(renderBoxModel);
      case 'scrollWidth':
        return getScrollWidth(renderBoxModel);
      case 'getBoundingClientRect':
        return getBoundingClientRect();
      default:
        return properties[key];
    }
  }

  @mustCallSuper
  void removeProperty(String key) {
    properties.remove(key);

    if (key == STYLE) {
      setProperty(STYLE, null);
    }
  }

  @mustCallSuper
  method(String name, List args) {
    switch (name) {
      case 'click':
        return click();
      case 'scroll':
        return scroll(args);
      case 'scrollBy':
        return scroll(args, isScrollBy: true);
    }
  }

  String getBoundingClientRect() {
    BoundingClientRect boundingClientRect;
    RenderBox sizedBox = renderBoxModel;
    if (isConnected) {
      // need to flush layout to get correct size
      elementManager.getRootRenderObject().owner.flushLayout();

      // Force flush layout.
      if (!sizedBox.hasSize) {
        sizedBox.markNeedsLayout();
        sizedBox.owner.flushLayout();
      }

      Offset offset = getOffset(sizedBox);
      Size size = sizedBox.size;
      boundingClientRect = BoundingClientRect(
        x: offset.dx,
        y: offset.dy,
        width: size.width,
        height: size.height,
        top: offset.dy,
        left: offset.dx,
        right: offset.dx + size.width,
        bottom: offset.dy + size.height,
      );
    } else {
      boundingClientRect = BoundingClientRect();
    }

    return boundingClientRect.toJSON();
  }

  double getOffsetX() {
    double offset = 0;
    if (renderBoxModel.attached) {
      Offset relative = getOffset(renderBoxModel);
      offset += relative.dx;
    }
    return offset;
  }

  double getOffsetY() {
    double offset = 0;
    if (renderBoxModel.attached) {
      Offset relative = getOffset(renderBoxModel);
      offset += relative.dy;
    }
    return offset;
  }

  Offset getOffset(RenderBox renderBox) {
    // need to flush layout to get correct size
    elementManager.getRootRenderObject().owner.flushLayout();

    Element element = _findContainingBlock(this);
    if (element == null) {
      element = elementManager.getRootElement();
    }
    return renderBox.localToGlobal(Offset.zero, ancestor: element.renderBoxModel);
  }

  @override
  void addEvent(String eventName) {
    if (eventHandlers.containsKey(eventName)) return; // Only listen once.
    bool isIntersectionObserverEvent = _isIntersectionObserverEvent(eventName);
    bool hasIntersectionObserverEvent = isIntersectionObserverEvent && _hasIntersectionObserverEvent(eventHandlers);
    super.addEventListener(eventName, _eventResponder);

    // bind pointer responder.
    addEventResponder(renderBoxModel);

    // Only add listener once for all intersection related event
    if (isIntersectionObserverEvent && !hasIntersectionObserverEvent) {
      renderBoxModel.addIntersectionChangeListener(handleIntersectionChange);
    }
  }

  void removeEvent(String eventName) {
    if (!eventHandlers.containsKey(eventName)) return; // Only listen once.
    super.removeEventListener(eventName, _eventResponder);

    // Remove pointer responder.
    removeEventResponder(renderBoxModel);

    // Remove listener when no intersection related event
    if (_isIntersectionObserverEvent(eventName) && !_hasIntersectionObserverEvent(eventHandlers)) {
      renderBoxModel.removeIntersectionChangeListener(handleIntersectionChange);
    }
  }

  void _eventResponder(Event event) {
    String json = jsonEncode([targetId, event]);
    emitUIEvent(elementManager.controller.view.contextId, json);
  }

  void click() {
    Event clickEvent = Event('click', EventInit());

    if (isConnected) {
      final RenderBox box = renderBoxModel;
      // HitTest will test rootView's every child (including
      // child's child), so must flush rootView every times,
      // or child may miss size.
      elementManager.getRootRenderObject().owner.flushLayout();

      // Position the center of element.
      Offset position = box.localToGlobal(box.size.center(Offset.zero), ancestor: elementManager.getRootRenderObject());
      final BoxHitTestResult boxHitTestResult = BoxHitTestResult();
      GestureBinding.instance.hitTest(boxHitTestResult, position);
      bool hitTest = true;
      Element currentElement = this;
      while (hitTest) {
        currentElement.handleClick(clickEvent);
        if (currentElement.parent != null) {
          currentElement = currentElement.parent;
          hitTest = currentElement.renderBoxModel.hitTest(boxHitTestResult, position: position);
        } else {
          hitTest = false;
        }
      }
    } else {
      // If element not in tree, click is fired and only response to itself.
      handleClick(clickEvent);
    }
  }

  Future<Uint8List> toBlob({double devicePixelRatio}) {
    if (devicePixelRatio == null) {
      devicePixelRatio = window.devicePixelRatio;
    }

    Completer<Uint8List> completer = Completer();

    RenderObject parent = renderBoxModel.parent;
    if (!renderBoxModel.isRepaintBoundary) {
      RenderBoxModel renderReplacedBoxModel;
      if (renderBoxModel is RenderLayoutBox) {
        renderReplacedBoxModel = createRenderLayout(this, prevRenderLayoutBox: renderBoxModel, repaintSelf: true);
      } else {
        renderReplacedBoxModel = _createRenderIntrinsic(this, prevRenderIntrinsic: renderBoxModel, repaintSelf: true);
      }

      if (parent is RenderObjectWithChildMixin<RenderBox>) {
        parent.child = null;
        parent.child = renderReplacedBoxModel;
      } else if (parent is ContainerRenderObjectMixin) {
        ContainerBoxParentData parentData = renderBoxModel.parentData;
        RenderObject previousSibling = parentData.previousSibling;
        parent.remove(renderBoxModel);
        parent.insert(renderReplacedBoxModel, after: previousSibling);
      }
      renderBoxModel = renderReplacedBoxModel;
    }

    renderBoxModel.markNeedsLayout();
    renderBoxModel.markNeedsPaint();

    SchedulerBinding.instance.addPostFrameCallback((_) async {
      Uint8List captured;
      if (renderBoxModel.size == Size.zero) {
        // Return a blob with zero length.
        captured = Uint8List(0);
      } else {
        Image image = await renderBoxModel.toImage(pixelRatio: devicePixelRatio);
        ByteData byteData = await image.toByteData(format: ImageByteFormat.png);
        captured = byteData.buffer.asUint8List();
      }

      completer.complete(captured);
    });

    return completer.future;
  }
}

RenderLayoutBox createRenderLayout(Element element, {RenderLayoutBox prevRenderLayoutBox, bool repaintSelf = false}) {
  CSSStyleDeclaration style = element.style;
  CSSDisplay display = CSSSizing.getDisplay(CSSStyleDeclaration.isNullOrEmptyValue(style[DISPLAY]) ? element.defaultDisplay : style[DISPLAY]);
  if (display == CSSDisplay.flex || display == CSSDisplay.inlineFlex) {
    RenderFlexLayout flexLayout;

    if (prevRenderLayoutBox == null) {
      if (repaintSelf) {
        flexLayout = RenderSelfRepaintFlexLayout(style: style, targetId: element.targetId, elementManager: element.elementManager);
      } else {
        flexLayout = RenderFlexLayout(style: style, targetId: element.targetId, elementManager: element.elementManager);
      }

    } else if (prevRenderLayoutBox is RenderFlowLayout) {
      if (prevRenderLayoutBox is RenderSelfRepaintFlowLayout) {
        if (repaintSelf) {
          // RenderSelfRepaintFlowLayout --> RenderSelfRepaintFlexLayout
          flexLayout = prevRenderLayoutBox.toFlexLayout();
        } else {
          // RenderSelfRepaintFlowLayout --> RenderFlexLayout
          flexLayout = prevRenderLayoutBox.toParentRepaintFlexLayout();
        }
      } else {
        if (repaintSelf) {
          // RenderFlowLayout --> RenderSelfRepaintFlexLayout
          flexLayout = prevRenderLayoutBox.toSelfRepaintFlexLayout();
        } else {
          // RenderFlowLayout --> RenderFlexLayout
          flexLayout = prevRenderLayoutBox.toFlexLayout();
        }
      }
    } else if (prevRenderLayoutBox is RenderFlexLayout) {
      if (prevRenderLayoutBox is RenderSelfRepaintFlexLayout) {
        if (repaintSelf) {
          // RenderSelfRepaintFlexLayout --> RenderSelfRepaintFlexLayout
          flexLayout = prevRenderLayoutBox;
          return flexLayout;
        } else {
          // RenderSelfRepaintFlexLayout --> RenderFlexLayout
          flexLayout = prevRenderLayoutBox.toParentRepaint();
        }
      } else {
        if (repaintSelf) {
          // RenderFlexLayout --> RenderSelfRepaintFlexLayout
          flexLayout = prevRenderLayoutBox.toSelfRepaint();
        } else {
          // RenderFlexLayout --> RenderFlexLayout
          flexLayout = prevRenderLayoutBox;
          return flexLayout;
        }
      }
    } else if (prevRenderLayoutBox is RenderRecyclerLayout) {
      flexLayout = prevRenderLayoutBox.toFlexLayout();
    }

    CSSFlexboxMixin.decorateRenderFlex(flexLayout, style);
    return flexLayout;
  } else if (display == CSSDisplay.block || display == CSSDisplay.none || display == CSSDisplay.inline || display == CSSDisplay.inlineBlock) {
    RenderFlowLayout flowLayout;

    if (prevRenderLayoutBox == null) {
      if (repaintSelf) {
        flowLayout = RenderSelfRepaintFlowLayout(style: style, targetId: element.targetId, elementManager: element.elementManager);
      } else {
        flowLayout = RenderFlowLayout(style: style, targetId: element.targetId, elementManager: element.elementManager);
      }
    } else if (prevRenderLayoutBox is RenderFlowLayout) {
      if (prevRenderLayoutBox is RenderSelfRepaintFlowLayout) {
        if (repaintSelf) {
          // RenderSelfRepaintFlowLayout --> RenderSelfRepaintFlowLayout
          flowLayout = prevRenderLayoutBox;
          return flowLayout;
        } else {
          // RenderSelfRepaintFlowLayout --> RenderFlowLayout
          flowLayout = prevRenderLayoutBox.toParentRepaint();
        }
      } else {
        if (repaintSelf) {
          // RenderFlowLayout --> RenderSelfRepaintFlowLayout
          flowLayout = prevRenderLayoutBox.toSelfRepaint();
        } else {
          // RenderFlowLayout --> RenderFlowLayout
          flowLayout = prevRenderLayoutBox;
          return flowLayout;
        }
      }
    } else if (prevRenderLayoutBox is RenderFlexLayout) {
      if (prevRenderLayoutBox is RenderSelfRepaintFlexLayout) {
        if (repaintSelf) {
          // RenderSelfRepaintFlexLayout --> RenderSelfRepaintFlowLayout
          flowLayout = prevRenderLayoutBox.toFlowLayout();
        } else {
          // RenderSelfRepaintFlexLayout --> RenderFlowLayout
          flowLayout = prevRenderLayoutBox.toParentRepaintFlowLayout();
        }
      } else {
        if (repaintSelf) {
          // RenderFlexLayout --> RenderSelfRepaintFlowLayout
          flowLayout = prevRenderLayoutBox.toSelfRepaintFlowLayout();
        } else {
          // RenderFlexLayout --> RenderFlowLayout
          flowLayout = prevRenderLayoutBox.toFlowLayout();
        }
      }
    } else if (prevRenderLayoutBox is RenderRecyclerLayout) {
      // RenderRecyclerLayout --> RenderFlowLayout
      flowLayout = prevRenderLayoutBox.toFlowLayout();
    }

    CSSFlowMixin.decorateRenderFlow(flowLayout, style);
    return flowLayout;
  } else if (display == CSSDisplay.sliver) {
    RenderRecyclerLayout renderRecyclerLayout;

    if (prevRenderLayoutBox == null) {
      renderRecyclerLayout = RenderRecyclerLayout(style: style, targetId: element.targetId, elementManager: element.elementManager);
    } else if (prevRenderLayoutBox is RenderFlowLayout) {
      renderRecyclerLayout = prevRenderLayoutBox.toRenderRecyclerLayout();
    } else if (prevRenderLayoutBox is RenderFlexLayout) {
      renderRecyclerLayout = prevRenderLayoutBox.toRenderRecyclerLayout();
    }

    return renderRecyclerLayout;
  } else {
    throw FlutterError('Not supported display type $display');
  }
}

RenderIntrinsic _createRenderIntrinsic(Element element, {RenderIntrinsic prevRenderIntrinsic, bool repaintSelf = false}) {
  RenderIntrinsic intrinsic;

  if (prevRenderIntrinsic == null) {
    if (repaintSelf) {
      intrinsic = RenderSelfRepaintIntrinsic(element.targetId, element.style, element.elementManager);
    } else {
      intrinsic = RenderIntrinsic(element.targetId, element.style, element.elementManager);
    }
  } else {
    if (prevRenderIntrinsic is RenderSelfRepaintIntrinsic) {
      if (repaintSelf) {
        // RenderSelfRepaintIntrinsic --> RenderSelfRepaintIntrinsic
        intrinsic = prevRenderIntrinsic;
      } else {
        // RenderSelfRepaintIntrinsic --> RenderIntrinsic
        intrinsic = prevRenderIntrinsic.toParentRepaint();
      }
    } else {
      if (repaintSelf) {
        // RenderIntrinsic --> RenderSelfRepaintIntrinsic
        intrinsic = prevRenderIntrinsic.toSelfRepaint();
      } else {
        // RenderIntrinsic --> RenderIntrinsic
        intrinsic = prevRenderIntrinsic;
      }
    }
  }
  return intrinsic;
}

RenderBoxModel createRenderBoxModel(Element element, {RenderBoxModel prevRenderBoxModel, bool repaintSelf = false}) {
  RenderBoxModel renderBoxModel = prevRenderBoxModel ?? element.renderBoxModel;

  if (renderBoxModel is RenderIntrinsic) {
    return _createRenderIntrinsic(element, prevRenderIntrinsic: prevRenderBoxModel, repaintSelf: repaintSelf);
  } else {
    return createRenderLayout(element, prevRenderLayoutBox: prevRenderBoxModel, repaintSelf: repaintSelf);
  }
}

Element _findContainingBlock(Element element) {
  Element _el = element?.parent;
  Element rootEl = element.elementManager.getRootElement();

  while (_el != null) {
    bool isElementNonStatic = _el.style[POSITION] != STATIC && _el.style[POSITION].isNotEmpty;
    bool hasTransform = _el.style[TRANSFORM].isNotEmpty;
    // https://www.w3.org/TR/CSS2/visudet.html#containing-block-details
    if (_el == rootEl || isElementNonStatic || hasTransform) {
      break;
    }
    _el = _el.parent;
  }
  return _el;
}

Element _findScrollContainer(Element element) {
  Element _el = element?.parent;
  Element rootEl = element.elementManager.getRootElement();

  while (_el != null) {
    List<CSSOverflowType> overflow = getOverflowTypes(_el.style);
    CSSOverflowType overflowX = overflow[0];
    CSSOverflowType overflowY = overflow[1];

    if (overflowX != CSSOverflowType.visible || overflowY != CSSOverflowType.visible || _el == rootEl) {
      break;
    }
    _el = _el.parent;
  }
  return _el;
}

List<Element> _findStickyChildren(Element element) {
  assert(element != null);
  List<Element> result = [];

  element.children.forEach((Element child) {
    List<CSSOverflowType> overflow = getOverflowTypes(child.style);
    CSSOverflowType overflowX = overflow[0];
    CSSOverflowType overflowY = overflow[1];

    if (child.isValidSticky) result.add(child);

    // No need to loop scrollable container children
    if (overflowX != CSSOverflowType.visible || overflowY != CSSOverflowType.visible) {
      return;
    }

    List<Element> mergedChildren = _findStickyChildren(child);
    mergedChildren.forEach((Element child) {
      result.add(child);
    });
  });

  return result;
}

bool _isIntersectionObserverEvent(String eventName) {
  return eventName == 'appear' || eventName == 'disappear' || eventName == 'intersectionchange';
}

bool _hasIntersectionObserverEvent(eventHandlers) {
  return eventHandlers.containsKey('appear') ||
      eventHandlers.containsKey('disappear') ||
      eventHandlers.containsKey('intersectionchange');
}

void _setPositionedChildParentData(RenderLayoutBox parentRenderLayoutBox, Element child) {
  var parentData;
  if (parentRenderLayoutBox is RenderFlowLayout) {
    parentData = RenderLayoutParentData();
  } else {
    parentData = RenderFlexParentData();
  }
  CSSStyleDeclaration style = child.style;

  RenderBoxModel childRenderBoxModel = child.renderBoxModel;
  childRenderBoxModel.parentData = CSSPositionedLayout.getPositionParentData(style, parentData);
}

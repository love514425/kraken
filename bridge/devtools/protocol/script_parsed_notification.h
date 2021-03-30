/*
 * Copyright (C) 2020 Alibaba Inc. All rights reserved.
 * Author: Kraken Team.
 */

#ifndef KRAKEN_DEBUGGER_PARSED_NOTIFICATION_H
#define KRAKEN_DEBUGGER_PARSED_NOTIFICATION_H

#include "devtools/protocol/error_support.h"
#include "devtools/protocol/location.h"
#include "devtools/protocol/stacktrace.h"
#include <memory>
#include <string>

namespace kraken {
namespace debugger {
class ScriptParsedNotification {
  KRAKEN_DISALLOW_COPY(ScriptParsedNotification);

public:
  static std::unique_ptr<ScriptParsedNotification> fromValue(rapidjson::Value *value, ErrorSupport *errors);

  ~ScriptParsedNotification() {}

  std::string getScriptId() {
    return m_scriptId;
  }
  void setScriptId(const std::string &value) {
    m_scriptId = value;
  }

  std::string getUrl() {
    return m_url;
  }
  void setUrl(const std::string &value) {
    m_url = value;
  }

  int getStartLine() {
    return m_startLine;
  }
  void setStartLine(int value) {
    m_startLine = value;
  }

  int getStartColumn() {
    return m_startColumn;
  }
  void setStartColumn(int value) {
    m_startColumn = value;
  }

  int getEndLine() {
    return m_endLine;
  }
  void setEndLine(int value) {
    m_endLine = value;
  }

  int getEndColumn() {
    return m_endColumn;
  }
  void setEndColumn(int value) {
    m_endColumn = value;
  }

  int getExecutionContextId() {
    return m_executionContextId;
  }
  void setExecutionContextId(int value) {
    m_executionContextId = value;
  }

  std::string getHash() {
    return m_hash;
  }
  void setHash(const std::string &value) {
    m_hash = value;
  }

  bool hasExecutionContextAuxData() {
    return m_executionContextAuxData.isJust();
  }
  rapidjson::Value *getExecutionContextAuxData(rapidjson::Value *defaultValue) {
    return m_executionContextAuxData.isJust() ? m_executionContextAuxData.fromJust() : defaultValue;
  }
  void setExecutionContextAuxData(std::unique_ptr<rapidjson::Value> value) {
    m_executionContextAuxData = std::move(value);
  }

  bool hasIsLiveEdit() {
    return m_isLiveEdit.isJust();
  }
  bool getIsLiveEdit(bool defaultValue) {
    return m_isLiveEdit.isJust() ? m_isLiveEdit.fromJust() : defaultValue;
  }
  void setIsLiveEdit(bool value) {
    m_isLiveEdit = value;
  }

  bool hasSourceMapURL() {
    return m_sourceMapURL.isJust();
  }
  std::string getSourceMapURL(const std::string &defaultValue) {
    return m_sourceMapURL.isJust() ? m_sourceMapURL.fromJust() : defaultValue;
  }
  void setSourceMapURL(const std::string &value) {
    m_sourceMapURL = value;
  }

  bool hasHasSourceURL() {
    return m_hasSourceURL.isJust();
  }
  bool getHasSourceURL(bool defaultValue) {
    return m_hasSourceURL.isJust() ? m_hasSourceURL.fromJust() : defaultValue;
  }
  void setHasSourceURL(bool value) {
    m_hasSourceURL = value;
  }

  bool hasIsModule() {
    return m_isModule.isJust();
  }
  bool getIsModule(bool defaultValue) {
    return m_isModule.isJust() ? m_isModule.fromJust() : defaultValue;
  }
  void setIsModule(bool value) {
    m_isModule = value;
  }

  bool hasLength() {
    return m_length.isJust();
  }
  int getLength(int defaultValue) {
    return m_length.isJust() ? m_length.fromJust() : defaultValue;
  }
  void setLength(int value) {
    m_length = value;
  }

  bool hasStackTrace() {
    return m_stackTrace.isJust();
  }
  StackTrace *getStackTrace(StackTrace *defaultValue) {
    return m_stackTrace.isJust() ? m_stackTrace.fromJust() : defaultValue;
  }
  void setStackTrace(std::unique_ptr<StackTrace> value) {
    m_stackTrace = std::move(value);
  }

  rapidjson::Value toValue(rapidjson::Document::AllocatorType &allocator) const;

  template <int STATE> class ScriptParsedNotificationBuilder {
  public:
    enum {
      NoFieldsSet = 0,
      ScriptIdSet = 1 << 1,
      UrlSet = 1 << 2,
      StartLineSet = 1 << 3,
      StartColumnSet = 1 << 4,
      EndLineSet = 1 << 5,
      EndColumnSet = 1 << 6,
      ExecutionContextIdSet = 1 << 7,
      HashSet = 1 << 8,
      AllFieldsSet = (ScriptIdSet | UrlSet | StartLineSet | StartColumnSet | EndLineSet | EndColumnSet |
                      ExecutionContextIdSet | HashSet | 0)
    };

    ScriptParsedNotificationBuilder<STATE | ScriptIdSet> &setScriptId(const std::string &value) {
      static_assert(!(STATE & ScriptIdSet), "property scriptId should not be set yet");
      m_result->setScriptId(value);
      return castState<ScriptIdSet>();
    }

    ScriptParsedNotificationBuilder<STATE | UrlSet> &setUrl(const std::string &value) {
      static_assert(!(STATE & UrlSet), "property url should not be set yet");
      m_result->setUrl(value);
      return castState<UrlSet>();
    }

    ScriptParsedNotificationBuilder<STATE | StartLineSet> &setStartLine(int value) {
      static_assert(!(STATE & StartLineSet), "property startLine should not be set yet");
      m_result->setStartLine(value);
      return castState<StartLineSet>();
    }

    ScriptParsedNotificationBuilder<STATE | StartColumnSet> &setStartColumn(int value) {
      static_assert(!(STATE & StartColumnSet), "property startColumn should not be set yet");
      m_result->setStartColumn(value);
      return castState<StartColumnSet>();
    }

    ScriptParsedNotificationBuilder<STATE | EndLineSet> &setEndLine(int value) {
      static_assert(!(STATE & EndLineSet), "property endLine should not be set yet");
      m_result->setEndLine(value);
      return castState<EndLineSet>();
    }

    ScriptParsedNotificationBuilder<STATE | EndColumnSet> &setEndColumn(int value) {
      static_assert(!(STATE & EndColumnSet), "property endColumn should not be set yet");
      m_result->setEndColumn(value);
      return castState<EndColumnSet>();
    }

    ScriptParsedNotificationBuilder<STATE | ExecutionContextIdSet> &setExecutionContextId(int value) {
      static_assert(!(STATE & ExecutionContextIdSet), "property executionContextId should not be set yet");
      m_result->setExecutionContextId(value);
      return castState<ExecutionContextIdSet>();
    }

    ScriptParsedNotificationBuilder<STATE | HashSet> &setHash(const std::string &value) {
      static_assert(!(STATE & HashSet), "property hash should not be set yet");
      m_result->setHash(value);
      return castState<HashSet>();
    }

    ScriptParsedNotificationBuilder<STATE> &setExecutionContextAuxData(std::unique_ptr<rapidjson::Value> value) {
      m_result->setExecutionContextAuxData(std::move(value));
      return *this;
    }

    ScriptParsedNotificationBuilder<STATE> &setIsLiveEdit(bool value) {
      m_result->setIsLiveEdit(value);
      return *this;
    }

    ScriptParsedNotificationBuilder<STATE> &setSourceMapURL(const std::string &value) {
      m_result->setSourceMapURL(value);
      return *this;
    }

    ScriptParsedNotificationBuilder<STATE> &setHasSourceURL(bool value) {
      m_result->setHasSourceURL(value);
      return *this;
    }

    ScriptParsedNotificationBuilder<STATE> &setIsModule(bool value) {
      m_result->setIsModule(value);
      return *this;
    }

    ScriptParsedNotificationBuilder<STATE> &setLength(int value) {
      m_result->setLength(value);
      return *this;
    }

    ScriptParsedNotificationBuilder<STATE> &setStackTrace(std::unique_ptr<StackTrace> value) {
      m_result->setStackTrace(std::move(value));
      return *this;
    }

    std::unique_ptr<ScriptParsedNotification> build() {
      static_assert(STATE == AllFieldsSet, "state should be AllFieldsSet");
      return std::move(m_result);
    }

  private:
    friend class ScriptParsedNotification;
    ScriptParsedNotificationBuilder() : m_result(new ScriptParsedNotification()) {}

    template <int STEP> ScriptParsedNotificationBuilder<STATE | STEP> &castState() {
      return *reinterpret_cast<ScriptParsedNotificationBuilder<STATE | STEP> *>(this);
    }

    std::unique_ptr<ScriptParsedNotification> m_result;
  };

  static ScriptParsedNotificationBuilder<0> create() {
    return ScriptParsedNotificationBuilder<0>();
  }

private:
  ScriptParsedNotification() {
    m_startLine = 0;
    m_startColumn = 0;
    m_endLine = 0;
    m_endColumn = 0;
    m_executionContextId = 0;
  }

  std::string m_scriptId;
  std::string m_url;
  int m_startLine;
  int m_startColumn;
  int m_endLine;
  int m_endColumn;
  int m_executionContextId;
  std::string m_hash;
  Maybe<rapidjson::Value> m_executionContextAuxData;
  Maybe<bool> m_isLiveEdit;
  Maybe<std::string> m_sourceMapURL;
  Maybe<bool> m_hasSourceURL;
  Maybe<bool> m_isModule;
  Maybe<int> m_length;
  Maybe<StackTrace> m_stackTrace;

  rapidjson::Document m_holder;
};
} // namespace debugger
} // namespace kraken

#endif // KRAKEN_DEBUGGER_PARSED_NOTIFICATION_H

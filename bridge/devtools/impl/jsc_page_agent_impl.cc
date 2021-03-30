/*
 * Copyright (C) 2020 Alibaba Inc. All rights reserved.
 * Author: Kraken Team.
 */

#include "jsc_page_agent_impl.h"
#include "devtools/inspector_session_impl.h"

namespace kraken::debugger {

JSCPageAgentImpl::JSCPageAgentImpl(kraken::debugger::InspectorSessionImpl *session,
                                   kraken::debugger::AgentContext &context)
  : m_session(session) {}

JSCPageAgentImpl::~JSCPageAgentImpl() {}

DispatchResponse JSCPageAgentImpl::enable() {
  m_enabled = true;
  return DispatchResponse::OK();
}

DispatchResponse JSCPageAgentImpl::disable() {
  m_enabled = false;
  return DispatchResponse::OK();
}

DispatchResponse JSCPageAgentImpl::reload(kraken::debugger::Maybe<bool> in_ignoreCache,
                                          kraken::debugger::Maybe<std::string> in_scriptToEvaluateOnLoad) {
  KRAKEN_LOG(VERBOSE) << "handle reload...";
  if (m_session && m_session->protocolHandler()) {
    m_session->protocolHandler()->handlePageReload();
    return DispatchResponse::OK();
  } else {
    return DispatchResponse::Error("session destroyed or protocol handler destroyed");
  }
}
} // namespace kraken

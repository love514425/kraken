/*
 * Copyright (C) 2020 Alibaba Inc. All rights reserved.
 * Author: Kraken Team.
 */

#ifndef KRAKEN_DEBUGGER_JSC_PAGE_AGENT_IMPL_H
#define KRAKEN_DEBUGGER_JSC_PAGE_AGENT_IMPL_H

#include "devtools/protocol/page_backend.h"
#include "kraken_foundation.h"

namespace kraken::debugger {

class InspectorSessionImpl;
class AgentContext;

class JSCPageAgentImpl : public PageBackend {
private:
  KRAKEN_DISALLOW_COPY_AND_ASSIGN(JSCPageAgentImpl);

public:
  JSCPageAgentImpl(InspectorSessionImpl *session, debugger::AgentContext &context);
  ~JSCPageAgentImpl() override;

  /***************** PageBackend *********************/
  DispatchResponse disable() override;
  DispatchResponse enable() override;

  DispatchResponse reload(Maybe<bool> in_ignoreCache, Maybe<std::string> in_scriptToEvaluateOnLoad) override;

private:
  bool m_enabled{false};

private:
  InspectorSessionImpl *m_session;
};
} // namespace kraken::debugger

#endif // KRAKEN_DEBUGGER_JSC_PAGE_AGENT_IMPL_H

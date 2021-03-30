/*
 * Copyright (C) 2020 Alibaba Inc. All rights reserved.
 * Author: Kraken Team.
 */

#ifndef KRAKEN_DEBUGGER_JSC_LOG_AGENT_IMPL_H
#define KRAKEN_DEBUGGER_JSC_LOG_AGENT_IMPL_H

#include "devtools/protocol/log_backend.h"
#include "devtools/protocol/log_frontend.h"

namespace kraken::debugger {
class InspectorSessionImpl;
class AgentContext;

class JSCLogAgentImpl : public LogBackend {
private:
  KRAKEN_DISALLOW_COPY_AND_ASSIGN(JSCLogAgentImpl);

public:
  JSCLogAgentImpl(InspectorSessionImpl *session, debugger::AgentContext &context);
  ~JSCLogAgentImpl() override;

  /***************** LogBackend *********************/
  DispatchResponse disable() override;
  DispatchResponse enable() override;
  DispatchResponse clear() override;
  void addMessageToConsole(std::unique_ptr<LogEntry> entry) override;

private:
  bool m_enabled{false};

private:
  InspectorSessionImpl *m_session;
  LogFrontend m_frontend;
};
} // namespace kraken::debugger

#endif // KRAKEN_DEBUGGER_JSC_LOG_AGENT_IMPL_H

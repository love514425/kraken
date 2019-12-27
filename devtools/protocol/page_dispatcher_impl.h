//
// Created by rowandjj on 2019/4/23.
//

#ifndef KRAKEN_DEBUGGER_DISPATCHER_IMPL_H
#define KRAKEN_DEBUGGER_DISPATCHER_IMPL_H


#include "devtools/protocol/dispatcher_base.h"
#include "devtools/protocol/page_backend.h"
#include "devtools/protocol/error_support.h"

#include <string>
#include <unordered_map>
#include <functional>

namespace kraken{
    namespace Debugger {
        class PageDispatcherImpl : public DispatcherBase {
        public:
            PageDispatcherImpl(FrontendChannel* frontendChannel, PageBackend* backend)
                    : DispatcherBase(frontendChannel)
                    , m_backend(backend) {
                m_dispatchMap["Page.disable"] =
                        std::bind(&PageDispatcherImpl::disable,this, std::placeholders::_1, std::placeholders::_2, std::placeholders::_3, std::placeholders::_4);
                m_dispatchMap["Page.enable"] =
                        std::bind(&PageDispatcherImpl::enable,this, std::placeholders::_1, std::placeholders::_2, std::placeholders::_3, std::placeholders::_4);
                m_dispatchMap["Page.reload"] =
                        std::bind(&PageDispatcherImpl::reload,this, std::placeholders::_1, std::placeholders::_2, std::placeholders::_3, std::placeholders::_4);
            }
            ~PageDispatcherImpl() override { }
            bool canDispatch(const std::string& method) override;
            void dispatch(uint64_t callId, const std::string& method, jsonRpc::JSONObject message) override ;
            std::unordered_map<std::string, std::string>& redirects() { return m_redirects; }

        protected:
            using CallHandler = std::function<void(uint64_t/*callId*/,const std::string&/*method*/,jsonRpc::JSONObject/*msg*/, ErrorSupport*)>;
            using DispatchMap = std::unordered_map<std::string, CallHandler>;

            DispatchMap m_dispatchMap;
            std::unordered_map<std::string, std::string> m_redirects;
            PageBackend* m_backend;

            void disable(uint64_t callId, const std::string& method, jsonRpc::JSONObject message, ErrorSupport*);
            void enable(uint64_t callId, const std::string& method, jsonRpc::JSONObject message, ErrorSupport*);
            void reload(uint64_t callId, const std::string& method, jsonRpc::JSONObject message, ErrorSupport*);
        };
    }
}


#endif //KRAKEN_DEBUGGER_DISPATCHER_IMPL_H

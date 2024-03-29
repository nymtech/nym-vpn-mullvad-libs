#include "stdafx.h"
#include "permitvpnrelay.h"
#include <winfw/mullvadguids.h>
#include <winfw/winfw.h>
#include <winfw/rules/shared.h>
#include <libwfp/filterbuilder.h>
#include <libwfp/conditionbuilder.h>
#include <libwfp/conditions/conditionprotocol.h>
#include <libwfp/conditions/conditionip.h>
#include <libwfp/conditions/conditionport.h>
#include <libwfp/conditions/conditionapplication.h>
#include <libcommon/error.h>

using namespace wfp::conditions;

namespace rules::multi
{

namespace
{

const GUID &LayerFromIp(const wfp::IpAddress &ip)
{
	switch (ip.type())
	{
		case wfp::IpAddress::Type::Ipv4: return FWPM_LAYER_ALE_AUTH_CONNECT_V4;
		case wfp::IpAddress::Type::Ipv6: return FWPM_LAYER_ALE_AUTH_CONNECT_V6;
		default:
		{
			THROW_ERROR("Missing case handler in switch clause");
		}
	};
}

const GUID &TranslateSublayer(PermitVpnRelay::Sublayer sublayer)
{
	switch (sublayer)
	{
		case PermitVpnRelay::Sublayer::Baseline: return MullvadGuids::SublayerBaseline();
		case PermitVpnRelay::Sublayer::Dns: return MullvadGuids::SublayerDns();
		default:
		{
			THROW_ERROR("Missing case handler in switch clause");
		}
	};
}

} // anonymous namespace

PermitVpnRelay::PermitVpnRelay
(
	const wfp::IpAddress &relay,
	uint16_t relayPort,
	WinFwProtocol protocol,
	const std::vector<std::wstring> &relayClients,
	Sublayer sublayer
)
	: m_relay(relay)
	, m_relayPort(relayPort)
	, m_protocol(protocol)
	, m_relayClients(relayClients)
	, m_sublayer(sublayer)
{
}

bool PermitVpnRelay::apply(IObjectInstaller &objectInstaller)
{
	wfp::FilterBuilder filterBuilder;

	//
	// #1 Permit outbound connections to relay.
	//

	filterBuilder
		.key(MullvadGuids::Filter_Baseline_PermitVpnRelay())
		.name(L"Permit outbound connections to VPN relay")
		.description(L"This filter is part of a rule that permits communication with a VPN relay")
		.provider(MullvadGuids::Provider())
		.layer(LayerFromIp(m_relay))
		.sublayer(TranslateSublayer(m_sublayer))
		.weight(wfp::FilterBuilder::WeightClass::Medium)
		.permit();

	wfp::ConditionBuilder conditionBuilder(LayerFromIp(m_relay));

	conditionBuilder.add_condition(ConditionIp::Remote(m_relay));
	conditionBuilder.add_condition(ConditionPort::Remote(m_relayPort));
	conditionBuilder.add_condition(CreateProtocolCondition(m_protocol));

	for(auto relayClient : m_relayClients) {
		conditionBuilder.add_condition(std::make_unique<ConditionApplication>(relayClient));
	}

	return objectInstaller.addFilter(filterBuilder, conditionBuilder);
}

}

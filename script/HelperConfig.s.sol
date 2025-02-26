// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Script, console2, console} from "forge-std/Script.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {LinkToken} from "test/mocks/LinkToken.sol";

abstract contract CodeConstants {
    /** VRF Mock values */
    uint96 public constant MOCK_BASE_FEE = 0.25 ether;
    uint96 public constant MOCK_GAS_PRICE_LINK = 1e9;
    // LINK / ETH price
    int256 public constant MOCK_WEI_PER_UINT_LINK = 4e15;

    uint256 public constant ETH_SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant LOCAL_CHAIN_ID = 31337;
}

contract HelperConfig is Script, CodeConstants {
    error HelperConfig__InvalidChainId(uint256 chainId);

    struct NetworkConfig {
        uint256 entranceFee;
        uint256 interval;
        address vrfCoordinatorV2;
        bytes32 gasLane;
        uint256 subscriptionId;
        uint32 callbackGasLimit;
        address link;
        address account;
    }

    NetworkConfig private localNetworkConfig;

    mapping(uint256 chainId => NetworkConfig config)
        private networkConfigByChainIdMapping;

    constructor() {
        networkConfigByChainIdMapping[
            ETH_SEPOLIA_CHAIN_ID
        ] = getSepoliaEthConfig();
        // Note: We skip doing the local config
    }

    function getConfig() public returns (NetworkConfig memory) {
        return getConfigByChainId(block.chainid);
    }

    function getConfigByChainId(
        uint256 chainId
    ) private returns (NetworkConfig memory) {
        if (
            networkConfigByChainIdMapping[chainId].vrfCoordinatorV2 !=
            address(0)
        ) {
            return networkConfigByChainIdMapping[chainId];
        } else if (chainId == LOCAL_CHAIN_ID) {
            return getOrCreateLocalAnvilChainConfig();
        } else {
            revert HelperConfig__InvalidChainId(chainId);
        }
    }

    function getSepoliaEthConfig() private pure returns (NetworkConfig memory) {
        return
            NetworkConfig({
                entranceFee: 0.01 ether,
                interval: 300, // 5 minutes
                vrfCoordinatorV2: 0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B,
                gasLane: 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae,
                subscriptionId: 79805096848979556860038321305584050586322729559945451277284318037489107738292, // subscriptionId that is created from the chainLink UI associated to the account 0x65CD26aB04cfda59c62c2338417ec7091A72cBF2
                callbackGasLimit: 500000, // 500_000
                link: 0x779877A7B0D9E8603169DdbD7836e478b4624789,
                account: 0x65CD26aB04cfda59c62c2338417ec7091A72cBF2
            });
    }

    function getOrCreateLocalAnvilChainConfig()
        private
        returns (NetworkConfig memory)
    {
        if (localNetworkConfig.vrfCoordinatorV2 != address(0)) {
            return localNetworkConfig;
        }

        console2.log(unicode"⚠️ You have deployed a mock conract!");
        console2.log("Make sure this was intentional");

        vm.startBroadcast();
        VRFCoordinatorV2_5Mock vrfCoordinatorV2_5Mock = new VRFCoordinatorV2_5Mock(
                MOCK_BASE_FEE,
                MOCK_GAS_PRICE_LINK,
                MOCK_WEI_PER_UINT_LINK
            );
        LinkToken linkToken = new LinkToken();
        vm.stopBroadcast();

        localNetworkConfig = NetworkConfig({
            entranceFee: 0.01 ether,
            interval: 30, // 30 seconds
            vrfCoordinatorV2: address(vrfCoordinatorV2_5Mock),
            gasLane: 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae, // doesn't matter in mock
            subscriptionId: 0, // If left as 0, our scripts will create one!
            callbackGasLimit: 500000, // 500_000
            link: address(linkToken), // doesn't matter in mock
            account: 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38 // DEFAULT_SENDER from Base.sol
        });

        return localNetworkConfig;
    }
}

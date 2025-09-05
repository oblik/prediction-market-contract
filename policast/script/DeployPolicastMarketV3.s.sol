// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {PolicastMarketV3} from "../src/V3.sol";

contract DeployPolicastMarketV3 is Script {
    address public bettingToken;
    uint256 public deployerPrivateKey;
    PolicastMarketV3 public market;

    function setUp() public {
        // Set the address of the ERC20 token to use for betting
        // Replace with your deployed ERC20 token address or deploy a mock
        bettingToken = vm.envAddress("BETTING_TOKEN");
        // Load deployer private key from environment variable
        deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    }

    function run() public {
        vm.startBroadcast(deployerPrivateKey);
        market = new PolicastMarketV3(bettingToken);
        vm.stopBroadcast();
    }
}

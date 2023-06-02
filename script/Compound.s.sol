// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import {CErc20Delegator} from "compound-protocol/contracts/CErc20Delegator.sol";
import {CErc20Delegate} from "compound-protocol/contracts/CErc20Delegate.sol";
import {ComptrollerInterface} from "compound-protocol/contracts/ComptrollerInterface.sol";
import {Unitroller} from "compound-protocol/contracts/Unitroller.sol";
import {SimplePriceOracle} from "compound-protocol/contracts/SimplePriceOracle.sol";
import {WhitePaperInterestRateModel} from "compound-protocol/contracts/WhitePaperInterestRateModel.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract CompoundDeployScript is Script {
    // Deploy CErc20Delegator, Unitroller, and related contracts
    function run() external {
        string memory seedPhrase = vm.readFile(".secret");
        uint256 privateKey = vm.deriveKey(seedPhrase, 0);
        vm.startBroadcast(privateKey);

        // Deploy underlying ERC20 token
        ERC20 underlyingToken = new ERC20("Underlying Token", "UTK");

        // Deploy SimplePriceOracle
        SimplePriceOracle priceOracle = new SimplePriceOracle();

        // Deploy WhitePaperInterestRateModel
        // 0% borrow and supply rates
        WhitePaperInterestRateModel interestRateModel = new WhitePaperInterestRateModel(0,0);

        // Deploy CErc20Delegate
        CErc20Delegate cErc20Delegate = new CErc20Delegate();

        // Deploy Unitroller
        Unitroller unitroller = new Unitroller();

        // Deploy CErc20Delegator
        CErc20Delegator cErc20Delegator = new CErc20Delegator(
            address(underlyingToken),
            ComptrollerInterface(address(unitroller)),
            interestRateModel,
            1e18,
            "cERC20",
            "cERC",
            18,
            payable(msg.sender),
            address(cErc20Delegate),
            ""
        );

        vm.stopBroadcast();
    }
}

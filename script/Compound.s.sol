// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import {CErc20Delegator} from "compound-protocal/contracts/CErc20Delegator.sol";
import {Erc20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {Unitroller} from "compound-protocal/contracts/Unitroller.sol";
import {SimplePriceOracle} from "compound-protocal/contracts/SimplePriceOracle.sol";
import {WhitePaperInterestRateModel} from "compound-protocal/contracts/WhitePaperInterestRateModel.sol";

contract CompoundDeployScript is Script {
    // Deploy CErc20Delegator, Unitroller, and related contracts
    function run() external {
        string memory seedPhrase = vm.readFile(".secret");
        uint256 privateKey = vm.deriveKey(seedPhrase, 0);
        vm.startBroadcast(privateKey);

        // Deploy underlying ERC20 token
        Erc20 underlyingToken = new Erc20("Underlying Token", "UTK", 18);

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
            msg.sender,
            address(cErc20Delegate),
            ""
        );

        cErc20Delegator._setPendingImplementation(address(cErc20Delegate));

        // Print contract addresses for verification
        vm.printAddress("CErc20Delegator", address(cErc20Delegator));
        vm.printAddress("Unitroller", address(unitroller));
        vm.printAddress("Underlying Token", address(underlyingToken));
        vm.printAddress("CErc20Delegate", address(cErc20Delegate));
        vm.printAddress("InterestRateModel", address(interestRateModel));
        vm.printAddress("PriceOracle", address(priceOracle));
        vm.stopBroadcast();
    }
}

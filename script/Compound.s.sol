// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import {CErc20Delegator} from "compound-protocol/contracts/CErc20Delegator.sol";
import {CErc20Delegate} from "compound-protocol/contracts/CErc20Delegate.sol";
import {ComptrollerInterface} from "compound-protocol/contracts/ComptrollerInterface.sol";
import {Comptroller} from "compound-protocol/contracts/Comptroller.sol";
import {Unitroller} from "compound-protocol/contracts/Unitroller.sol";
import {CToken} from "compound-protocol/contracts/CToken.sol";
import {SimplePriceOracle} from "compound-protocol/contracts/SimplePriceOracle.sol";
import {WhitePaperInterestRateModel} from "compound-protocol/contracts/WhitePaperInterestRateModel.sol";
import {InterestRateModel} from "compound-protocol/contracts/InterestRateModel.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract CompoundDeployScript is Script {
    ERC20 public underlyingToken;
    CErc20Delegator public cErc20;
    CErc20Delegate public cErc20Delegate;
    Unitroller public unitroller;
    Comptroller public comptroller;
    Comptroller public unitrollerProxy;
    WhitePaperInterestRateModel public whitePaper;
    SimplePriceOracle public priceOracle;

    function deploy() public {
        // reveal if you want to use a private key
        // string memory seedPhrase = vm.readFile(".secret");
        // uint256 privateKey = vm.deriveKey(seedPhrase, 0);
        // vm.startBroadcast(privateKey);
        vm.startBroadcast();
        // Deploy underlying ERC20 token
        underlyingToken = new ERC20("Underlying Token", "UTK");

        // Deploy SimplePriceOracle
        priceOracle = new SimplePriceOracle();

        // Deploy WhitePaperInterestRateModel
        // utilizationRate * multiplierPerBlock + baseRatePerBlock
        // utilizationRate = 0, borrow rate = baseRatePerBlock (5%)
        // utilizationRate = 1, borrow rate = baseRatePerBlock + multiplierPerBlock (17%)
        whitePaper = new WhitePaperInterestRateModel(
            5e16, // 5%: baseRatePerYear
            12e16 // 12%: multiplierPerYear
        );

        // Deploy Unitroller and Comptroller
        // unitroller is proxy
        // comptroller is implementation
        unitroller = new Unitroller();
        comptroller = new Comptroller();
        // In the proxy contract, add a management function to allow the administrator to set the address of the logic implementation contract.
        // In the unitroller contract, it adds a function to transfer the ownership of the proxy,
        // and its impl contract needs to accept the transfer to prevent accidentally upgrading to an invalid contract.
        unitroller._setPendingImplementation(address(comptroller));
        comptroller._become(unitroller);

        unitrollerProxy = Comptroller(address(unitroller));
        unitrollerProxy._setPriceOracle(priceOracle);
        unitrollerProxy._setCloseFactor(500000000000000000);
        unitrollerProxy._setLiquidationIncentive(1080000000000000000);

        // Deploy CErc20Delegate
        cErc20Delegate = new CErc20Delegate();

        bytes memory data = new bytes(0x00);

        // Deploy CErc20Delegator
        cErc20 = new CErc20Delegator(
            address(underlyingToken),
            ComptrollerInterface(address(unitroller)),
            InterestRateModel(address(whitePaper)),
            1e18,
            "cERC20",
            "cERC",
            18,
            payable(msg.sender),
            address(cErc20Delegate),
            data
        );

        cErc20._setImplementation(address(cErc20Delegate), false, data);

        // set underlying price
        priceOracle.setUnderlyingPrice(CToken(address(cErc20)), 1e18);
        // support market
        unitrollerProxy._supportMarket(CToken(address(cErc20)));
        unitrollerProxy._setCollateralFactor(
            CToken(address(cErc20)),
            600000000000000000 // 60%
        );
        vm.stopBroadcast();
    }

    // interestRate, priceOracle, comptorller, ctoken
    // Deploy CErc20Delegator, Unitroller, and related contracts
    function run() external {
        deploy();
    }
}

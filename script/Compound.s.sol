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
        // Deploy underlying ERC20 token
        Erc20 underlyingToken = new Erc20("Underlying Token", "UNDERLYING", 18);

        // Deploy SimplePriceOracle
        SimplePriceOracle priceOracle = new SimplePriceOracle();

        // Deploy WhitePaperInterestRateModel
        WhitePaperInterestRateModel interestRateModel = new WhitePaperInterestRateModel();
        interestRateModel.init(0, 0, 0, 0); // Set borrow and supply rates to 0%

        // Deploy Unitroller
        Unitroller unitroller = new Unitroller();

        // Deploy CErc20Delegator
        // Deploy CErc20Delegator
        CErc20Delegator cToken = new CErc20Delegator(
            address(underlyingToken),
            address(unitroller),
            address(interestRateModel),
            1e18,
            "cToken",
            "CTKN",
            18,
            payable(msg.sender),
            address(0), // Replace with your implementation contract address
            ""
        );

        // Set cToken's implementation
        cToken._setImplementation(address(implementation), false, "");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

//cToken
import "compound-protocol/contracts/CErc20Delegator.sol";
import "compound-protocol/contracts/CErc20Delegate.sol";
import "compound-protocol/contracts/CToken.sol";
//comptroller
import "compound-protocol/contracts/Unitroller.sol";
import "compound-protocol/contracts/Comptroller.sol";
//interestModel
import "compound-protocol/contracts/WhitePaperInterestRateModel.sol";
//priceOracle
import "compound-protocol/contracts/SimplePriceOracle.sol";

contract CompoundDeployScript is Script {
    ERC20 public underlyingToken;
    CErc20Delegator public cErc20;
    CErc20Delegate public cErc20Delegate;
    Unitroller public unitroller;
    Comptroller public comptroller;
    Comptroller public unitrollerProxy;
    WhitePaperInterestRateModel public whitePaper;
    SimplePriceOracle public priceOracle;

    // deploy CErc20Delegator
    function deployCErc20(
        address deployer,
        address _underlyingToken,
        string memory _name,
        string memory _symbol
    ) public returns (CErc20Delegator) {
        CErc20Delegator _cErc20 = new CErc20Delegator(
            _underlyingToken,
            ComptrollerInterface(address(unitroller)),
            InterestRateModel(address(whitePaper)),
            1e18,
            _name,
            _symbol,
            18,
            payable(deployer),
            address(cErc20Delegate),
            new bytes(0x00)
        );

        return _cErc20;
    }

    function deploy(address deployer) public {
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
        cErc20 = deployCErc20(
            deployer,
            address(underlyingToken),
            "cERC20",
            "cERC"
        );

        cErc20._setImplementation(address(cErc20Delegate), false, data);

        // set underlying price
        priceOracle.setDirectPrice(address(underlyingToken), 1e18);

        // support market
        unitrollerProxy._supportMarket(CToken(address(cErc20)));
        unitrollerProxy._setCollateralFactor(
            CToken(address(cErc20)),
            600000000000000000 // 60%
        );
    }

    // interestRate, priceOracle, comptorller, ctoken
    // Deploy CErc20Delegator, Unitroller, and related contracts
    function run() external {
        // reveal if you want to use a private key
        // string memory seedPhrase = vm.readFile(".secret");
        // uint256 privateKey = vm.deriveKey(seedPhrase, 0);
        // vm.startBroadcast(privateKey);
        vm.startBroadcast();
        deploy(msg.sender);
        vm.stopBroadcast();
    }
}

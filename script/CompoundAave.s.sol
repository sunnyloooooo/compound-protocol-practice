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

contract CompoundAaveDeployScript is Script {
    address constant USDCAddress = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant UNIAddress = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
    // decimals of cERC20 is 18
    IERC20 public USDC = IERC20(USDCAddress);
    IERC20 public UNI = IERC20(UNIAddress);
    CErc20Delegator public cUSDC;
    CErc20Delegator public cUNI;
    CErc20Delegate public cUSDCDelegate;
    CErc20Delegate public cUNIDelegate;
    Unitroller public unitroller;
    Comptroller public comptroller;
    Comptroller public unitrollerProxy;
    WhitePaperInterestRateModel public whitePaper;
    SimplePriceOracle public priceOracle;

    // deploy CErc20Delegator
    function deployCErc20(
        address deployer,
        address _underlyingToken,
        address _cErc20Delegate,
        uint _initialExchangeRateMantissa,
        string memory _name,
        string memory _symbol
    ) public returns (CErc20Delegator) {
        CErc20Delegator _cErc20 = new CErc20Delegator(
            _underlyingToken,
            ComptrollerInterface(address(unitroller)),
            InterestRateModel(address(whitePaper)),
            _initialExchangeRateMantissa,
            _name,
            _symbol,
            18,
            payable(deployer),
            _cErc20Delegate,
            new bytes(0x00)
        );

        return _cErc20;
    }

    function deploy(address deployer) public {
        // Deploy SimplePriceOracle
        priceOracle = new SimplePriceOracle();

        // Deploy WhitePaperInterestRateModel
        whitePaper = new WhitePaperInterestRateModel(
            5e16, // 5%: baseRatePerYear
            12e16 // 12%: multiplierPerYear
        );

        unitroller = new Unitroller();
        comptroller = new Comptroller();
        unitroller._setPendingImplementation(address(comptroller));
        comptroller._become(unitroller);

        unitrollerProxy = Comptroller(address(unitroller));
        unitrollerProxy._setPriceOracle(priceOracle);
        unitrollerProxy._setCloseFactor(5e17); // 50%
        unitrollerProxy._setLiquidationIncentive(1.08e18); // 108% , 100% is collateral, 8% is reward

        // Deploy CErc20Delegate
        cUSDCDelegate = new CErc20Delegate();
        cUNIDelegate = new CErc20Delegate();

        bytes memory data = new bytes(0x00);

        // Deploy CErc20Delegator
        cUSDC = deployCErc20(
            deployer,
            USDCAddress,
            address(cUSDCDelegate),
            // 10 * 10 ** ( 18 - 18:ctoken + 6:usdc )
            10 * (10 ** 6),
            "cUSCD",
            "cUSDC"
        );

        cUSDC._setImplementation(address(cUSDCDelegate), false, data);

        cUNI = deployCErc20(
            deployer,
            UNIAddress,
            address(cUNIDelegate),
            // 10 * 10 ** ( 18 - 18:ctoken + 18:usdc )
            10 * 10 ** 18,
            "cUNI",
            "cUNI"
        );

        cUNI._setImplementation(address(cUNIDelegate), false, data);
        cUNI._setReserveFactor(25e16);

        // set underlying price
        // uint256 price = ( 10**18 / 10**erc20Decimals ) * 1e18
        priceOracle.setUnderlyingPrice(CToken(address(cUSDC)), 1e30); // $1
        priceOracle.setUnderlyingPrice(CToken(address(cUNI)), 5e18); // $5

        // support market
        unitrollerProxy._supportMarket(CToken(address(cUSDC)));
        unitrollerProxy._setCollateralFactor(
            CToken(address(cUSDC)),
            500000000000000000 // 50%
        );

        unitrollerProxy._supportMarket(CToken(address(cUNI)));
        unitrollerProxy._setCollateralFactor(
            CToken(address(cUNI)),
            500000000000000000 // 50%
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

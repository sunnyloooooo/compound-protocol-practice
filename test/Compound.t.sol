// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "compound-protocol/contracts/CErc20Delegator.sol";
import "compound-protocol/contracts/CToken.sol";
import {CompoundDeployScript} from "../script/Compound.s.sol";

contract CompoundTest is CompoundDeployScript, Test {
    address public user;
    address admin;
    address liquidator;
    ERC20 public underlyingTokenNo2;
    CErc20Delegator public cErc20No2;

    function setUp() public {
        user = makeAddr("User");
        admin = makeAddr("Admin");
        liquidator = makeAddr("Liquidator");
        vm.startPrank(admin);
        super.deploy(admin);
        uint256 initialBalance = 10000 * 10 ** underlyingToken.decimals();
        deal(address(underlyingToken), user, initialBalance);
        deal(address(underlyingToken), liquidator, initialBalance);
        deal(address(underlyingToken), admin, initialBalance);
        deployCErc20No2();
        uint256 initialBalanceNo2 = 10000 * 10 ** underlyingTokenNo2.decimals();
        deal(address(underlyingTokenNo2), user, initialBalanceNo2);
        deal(address(underlyingTokenNo2), liquidator, initialBalanceNo2);
        deal(address(underlyingTokenNo2), admin, initialBalanceNo2);

        vm.stopPrank();
    }

    function deployCErc20No2() public {
        // Deploy the second cERC20 contract, and underlying token call UTK2.
        underlyingTokenNo2 = new ERC20("Underlying Token No2", "UTK2");
        cErc20No2 = super.deployCErc20(
            admin,
            address(underlyingTokenNo2),
            "cERC20No2",
            "cERC2"
        );

        // Set the price of a cErc20No2 to $100
        priceOracle.setDirectPrice(address(underlyingTokenNo2), 100 * 10 ** 18);

        // support the market of cErc20No2
        unitrollerProxy._supportMarket(CToken(address(cErc20No2)));
        // Set the collateral factor of cErc20No2 to 50%
        unitrollerProxy._setCollateralFactor(
            CToken(address(cErc20No2)),
            500000000000000000 // 50%
        );
    }

    function mint100CErc20() public {
        vm.startPrank(user);
        // user calls the enterMarkets method of unitroller, because there is a check in the mintAllowed function: require(markets[cToken].isListed), so even in mint, you need to call enterMarkets first
        address[] memory addr = new address[](1);
        addr[0] = address(cErc20);
        unitrollerProxy.enterMarkets(addr);
        // at this time, after user calls enterMarkets, the global variable accountAssets[user] = cToken[cErc20], markets[cErc20]={true, 60%，{user:true},false}

        // user calls the mint method of cErc20
        underlyingToken.approve(
            address(cErc20),
            underlyingToken.balanceOf(user)
        );
        cErc20.mint(100 * 10 ** underlyingToken.decimals());

        vm.stopPrank();
    }

    function borrow() public {
        vm.startPrank(admin);
        underlyingToken.approve(
            address(cErc20),
            underlyingToken.balanceOf(admin)
        );
        cErc20.mint(underlyingToken.balanceOf(admin));
        vm.stopPrank();
        vm.startPrank(user);
        address[] memory addr = new address[](2);
        addr[0] = address(cErc20No2);
        addr[1] = address(cErc20);
        unitrollerProxy.enterMarkets(addr);
        // User mints cToken with 1 cErc20No2
        uint256 initUnderlyingTokenNo2Balance = underlyingTokenNo2.balanceOf(
            user
        );
        underlyingTokenNo2.approve(
            address(cErc20No2),
            underlyingTokenNo2.balanceOf(user)
        );
        uint256 mintAmount = 1 * 10 ** underlyingTokenNo2.decimals();
        cErc20No2.mint(mintAmount);
        assertEq(
            underlyingTokenNo2.balanceOf(user),
            initUnderlyingTokenNo2Balance - mintAmount
        );
        // User uses cErc20No2 as collateral to borrow 50 token A
        cErc20.borrow(50 * 10 ** 18);
        vm.stopPrank();
    }

    function repay() public {
        vm.startPrank(user);
        // approve
        underlyingToken.approve(address(cErc20), 50 * 10 ** 18);
        cErc20.repayBorrow(50 * 10 ** 18);
        vm.stopPrank();
    }

    function test_compound_mint() public {
        mint100CErc20();
        // due to exchange rate = 1
        assertEq(cErc20.balanceOf(user), 100 * 10 ** cErc20.decimals());
        assertEq(cErc20.totalSupply(), 100 * 10 ** cErc20.decimals());
        // because of Utilization = 0%, so supplyRatePerBlock = 0
        assertEq(cErc20.supplyRatePerBlock(), 0);
        // User liquidity: UnderlyingToken * 0.6 * price
        (, uint liquidity, ) = unitrollerProxy.getAccountLiquidity(user);
        assertEq(liquidity, 60 * 10 ** cErc20.decimals());
    }

    function test_compound_redeem() public {
        mint100CErc20();
        vm.startPrank(user);
        // user calls the redeem method of cErc20
        cErc20.redeem(cErc20.balanceOf(user));
        vm.stopPrank();
        assertEq(
            underlyingToken.balanceOf(user),
            10000 * 10 ** underlyingToken.decimals()
        );
        (, uint liquidity, ) = unitrollerProxy.getAccountLiquidity(user);
        assertEq(liquidity, 0);
    }

    function test_compound_borrow() public {
        uint256 initUnderlyingTokenBalance = underlyingToken.balanceOf(user);
        borrow();
        // check the balance of user will be balance of user before borrow - 50
        assertEq(
            underlyingToken.balanceOf(user),
            (50 * 10 ** 18 + initUnderlyingTokenBalance)
        );
    }

    function test_compound_repay() public {
        uint256 initUnderlyingTokenBalance = underlyingToken.balanceOf(user);
        borrow();
        repay();
        // check the balance of user will be balance of user before borrow
        assertEq(underlyingToken.balanceOf(user), initUnderlyingTokenBalance);
    }

    // Adjust the collateral factor of token B to let User be liquidated by User2
    function test_compound_liquidation_by_collateral_factor() public {
        borrow();
        vm.startPrank(admin);

        // Set the collateral factor of cErc20No2 to 40%
        unitrollerProxy._setCollateralFactor(
            CToken(address(cErc20No2)),
            400000000000000000 // 40%
        );

        vm.stopPrank();

        vm.startPrank(liquidator);
        underlyingToken.approve(address(cErc20), 100 * 10 ** 18);
        (uint error, uint liquidity, uint shortfall) = unitrollerProxy
            .getAccountLiquidity(user);

        // Check whether it can be liquidated
        if (error == 0 && liquidity == 0 && shortfall > 0) {
            cErc20.liquidateBorrow(
                user,
                ((50 * 10 ** 18) * 50) / 100,
                CTokenInterface(address(cErc20No2))
            );
        }
    }

    // Adjust the price of token B in oracle, and let User be liquidated by User2
    function test_compound_liquidation_by_price() public {
        borrow();
        vm.startPrank(admin);
        // origin price is 100, change to 30
        priceOracle.setDirectPrice(address(underlyingTokenNo2), 30 * 10 ** 18);
        vm.stopPrank();

        vm.startPrank(liquidator);
        underlyingToken.approve(address(cErc20), 100 * 10 ** 18);
        (uint error, uint liquidity, uint shortfall) = unitrollerProxy
            .getAccountLiquidity(user);

        // Check whether it can be liquidated
        if (error == 0 && liquidity == 0 && shortfall > 0) {
            cErc20.liquidateBorrow(
                user,
                ((50 * 10 ** 18) * 50) / 100,
                CTokenInterface(address(cErc20No2))
            );
        }
    }
}

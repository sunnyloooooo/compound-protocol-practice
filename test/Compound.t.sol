// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "compound-protocol/contracts/CErc20Delegator.sol";
import "compound-protocol/contracts/CToken.sol";
import {CompoundDeployScript} from "../script/Compound.s.sol";

contract CompoundTest is CompoundDeployScript, Test {
    address public user;

    function setUp() public {
        super.deploy();

        user = makeAddr("User");
        uint256 initialBalance = 10000 * 10 ** underlyingToken.decimals();
        deal(address(underlyingToken), user, initialBalance);

        super.deployCErc20No2();
        uint256 initialBalanceNo2 = 10000 * 10 ** underlyingTokenNo2.decimals();
        deal(address(underlyingTokenNo2), user, initialBalanceNo2);
    }

    function mint() public {
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
        vm.startPrank(user);
        address[] memory addr = new address[](1);
        addr[0] = address(cErc20No2);
        unitrollerProxy.enterMarkets(addr);
        // User mints cToken with 1 cErc20No2
        uint256 underlyingTokenNo2Balance = underlyingTokenNo2.balanceOf(user);
        underlyingTokenNo2.approve(
            address(cErc20No2),
            underlyingTokenNo2.balanceOf(user)
        );
        uint256 mintAmount = 1 * 10 ** underlyingTokenNo2.decimals();
        cErc20No2.mint(mintAmount);
        assertEq(
            underlyingTokenNo2.balanceOf(user),
            underlyingTokenNo2Balance - mintAmount
        );
        // User uses cErc20No2 as collateral to borrow 50 token A
        cErc20No2.borrow((mintAmount * 50) / 100);
        assertEq(
            underlyingTokenNo2.balanceOf(user),
            (underlyingTokenNo2Balance - mintAmount + ((mintAmount * 50) / 100))
        );

        vm.stopPrank();
    }

    function test_compound_mint() public {
        mint();
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
        mint();
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
        borrow();
    }

    // Adjust the collateral factor of token B to let User be liquidated by User2
    function test_compound_liquidation_by_collateral_factor() public {
        borrow();
        unitrollerProxy._setCollateralFactor(
            CToken(address(cErc20No2)),
            600000000000000000 // 60%
        );
    }

    // Adjust the price of token B in oracle, and let User be liquidated by User2
    function test_compound_liquidation_by_oracle() public {
        borrow();
        priceOracle.setUnderlyingPrice(CToken(address(cErc20No2)), 1e18);
    }
}

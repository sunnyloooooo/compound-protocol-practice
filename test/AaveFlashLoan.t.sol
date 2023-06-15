// 在下方實作
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "compound-protocol/contracts/CErc20Delegator.sol";
import "compound-protocol/contracts/CToken.sol";
import {CompoundAaveDeployScript} from "../script/CompoundAave.s.sol";
import "../contracts/AaveFlashLoan.sol";

contract AaveFlashLoanTest is CompoundAaveDeployScript, Test {
    address public user;
    address admin;
    address liquidator;
    uint256 constant user_mint_amount = 1000 * 10 ** 18;
    uint256 constant user_borrow_amount = 2500 * 10 ** 18;
    CErc20Delegator public cErc20No2;

    AaveFlashLoan public aaveFlashLoan;

    function setUp() public {
        string memory rpc = vm.envString("MAINNET_RPC_URL");
        vm.createSelectFork(rpc, 17465000);

        user = makeAddr("User");
        admin = makeAddr("Admin");
        liquidator = makeAddr("Liquidator");
        vm.startPrank(admin);
        super.deploy(admin);

        aaveFlashLoan = new AaveFlashLoan();

        uint256 initialBalance = 50_000 * 10 ** 18;
        deal(address(USDC), address(aaveFlashLoan), initialBalance);
        deal(address(USDC), admin, 10_000 * 10 ** 18);
        USDC.approve(address(cUSDC), 10_000 * 10 ** 18);
        cUSDC.mint(10_000 * 10 ** 18);

        // give user 1000 UNI as collateral
        deal(address(UNI), user, user_mint_amount);
        vm.label(address(aaveFlashLoan), "Flash Loan");
        vm.stopPrank();
    }

    // user borrow 2500 USDC with 1000 UNI as collateral
    function user_borrow() public {
        vm.startPrank(user);
        address[] memory addr = new address[](1);
        addr[0] = address(cUNI);
        unitrollerProxy.enterMarkets(addr);

        UNI.approve(address(cUNI), user_mint_amount);
        cUNI.mint(user_mint_amount);
        assertEq(UNI.balanceOf(user), 0);
        cUSDC.borrow(user_borrow_amount);
        vm.stopPrank();
    }

    function test_compound_borrow_usdc() public {
        user_borrow();
    }

    function test_aave_flash_loan_of_liquidate_user() public {
        user_borrow();
        vm.startPrank(admin);
        priceOracle.setUnderlyingPrice(CToken(address(cUNI)), 4 * 10 ** 18);
        vm.stopPrank();

        vm.startPrank(liquidator);
        aaveFlashLoan.execute(
            liquidator,
            user,
            UNIAddress,
            USDCAddress,
            USDC,
            UNI,
            unitrollerProxy,
            cUSDC,
            cUNI,
            cUSDCDelegate,
            cUNIDelegate
        );

        vm.stopPrank();
        // console.log(IERC20(usdcTokenAddress).balanceOf(liquidator));
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "compound-protocol/contracts/CErc20Delegator.sol";
import "compound-protocol/contracts/CToken.sol";
import {CompoundAaveDeployScript} from "../script/CompoundAave.s.sol";
import "../contracts/AaveFlashLoan.sol";

contract AaveFlashLoanTest is CompoundAaveDeployScript, Test {
    address public user1;
    address admin;
    address liquidator;
    uint256 constant user1_mint_uni_amount = 1000 * 10 ** 18;
    uint256 constant user1_borrow_usdc_amount = 2500 * 10 ** 6;
    CErc20Delegator public cErc20No2;
    AaveFlashLoan public aaveFlashLoan;

    function setUp() public {
        string memory rpc = vm.envString("MAINNET_RPC_URL");
        vm.createSelectFork(rpc, 17465000);
        user1 = makeAddr("User1");
        admin = makeAddr("Admin");
        liquidator = makeAddr("Liquidator");
        vm.startPrank(admin);
        super.deploy(admin);
        aaveFlashLoan = new AaveFlashLoan();
        uint256 initialBalance = 50_000 * 10 ** 18;
        // deal(address(USDC), address(aaveFlashLoan), initialBalance);
        deal(address(USDC), admin, 10_000 * 10 ** 18);
        USDC.approve(address(cUSDC), 10_000 * 10 ** 18);
        cUSDC.mint(10_000 * 10 ** 18);

        // give user1 1000 UNI as collateral
        deal(address(UNI), user1, user1_mint_uni_amount);
        vm.label(address(aaveFlashLoan), "Flash Loan");
        vm.stopPrank();
    }

    // user1 borrow 2500 USDC with 1000 UNI as collateral
    function user1_borrow() public {
        vm.startPrank(user1);
        address[] memory addr = new address[](1);
        addr[0] = address(cUNI);
        unitrollerProxy.enterMarkets(addr);

        UNI.approve(address(cUNI), user1_mint_uni_amount);
        cUNI.mint(user1_mint_uni_amount);
        assertEq(UNI.balanceOf(user1), 0);
        cUSDC.borrow(user1_borrow_usdc_amount);
        vm.stopPrank();
    }

    function test_compound_borrow_usdc() public {
        user1_borrow();
    }

    function test_aave_flash_loan_of_liquidate_user1() public {
        user1_borrow();
        vm.startPrank(admin);
        priceOracle.setUnderlyingPrice(CToken(address(cUNI)), 4 * 10 ** 18);
        vm.stopPrank();

        vm.startPrank(liquidator);
        aaveFlashLoan.execute(
            liquidator,
            user1,
            USDCAddress,
            UNIAddress,
            USDC,
            UNI,
            cUSDC,
            cUNI,
            cUSDCDelegate,
            cUNIDelegate,
            unitrollerProxy
        );

        assertEq(USDC.balanceOf(address(aaveFlashLoan)), 63638693);
        vm.stopPrank();
    }
}

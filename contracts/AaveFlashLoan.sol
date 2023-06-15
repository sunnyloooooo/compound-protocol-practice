pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {ERC20} from "openzeppelin/token/ERC20/ERC20.sol";
import {IFlashLoanSimpleReceiver, IPoolAddressesProvider, IPool} from "aave-v3-core/contracts/flashloan/interfaces/IFlashLoanSimpleReceiver.sol";
import {CErc20Delegator} from "compound-protocol/contracts/CErc20Delegator.sol";
import {CErc20Delegate} from "compound-protocol/contracts/CErc20Delegate.sol";
import {CErc20} from "compound-protocol/contracts/CErc20.sol";
import {CToken} from "compound-protocol/contracts/CToken.sol";
import {CTokenInterface} from "compound-protocol/contracts/CTokenInterfaces.sol";
import {ComptrollerInterface} from "compound-protocol/contracts/ComptrollerInterface.sol";
import {InterestRateModel} from "compound-protocol/contracts/InterestRateModel.sol";
import {Comptroller} from "compound-protocol/contracts/Comptroller.sol";
import {WhitePaperInterestRateModel} from "compound-protocol/contracts/WhitePaperInterestRateModel.sol";
import {Unitroller} from "compound-protocol/contracts/Unitroller.sol";
import {SimplePriceOracle} from "compound-protocol/contracts/SimplePriceOracle.sol";
import {PriceOracle} from "compound-protocol/contracts/PriceOracle.sol";
import {ISwapRouter} from "v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {TransferHelper} from "v3-periphery/contracts/libraries/TransferHelper.sol";

// TODO: Inherit IFlashLoanSimpleReceiver
contract AaveFlashLoan is IFlashLoanSimpleReceiver {
    address constant POOL_ADDRESSES_PROVIDER =
        0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;
    address UNISWAP_V3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    struct CallbackData {
        address UNIAddress;
        address USDCAddress;
        IERC20 USDC;
        IERC20 UNI;
        address liquidator;
        address borrower;
        Comptroller unitrollerProxy;
        CErc20Delegator cUSDC;
        CErc20Delegator cUNI;
        CErc20Delegate cUNIDelegate;
        CErc20Delegate cUSDCDelegate;
    }

    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external returns (bool) {
        CallbackData memory callBackData = abi.decode(params, (CallbackData));

        callBackData.USDC.approve(address(callBackData.cUSDC), 1250e18);
        (uint error, uint liquidity, uint shortfall) = callBackData
            .unitrollerProxy
            .getAccountLiquidity(address(callBackData.borrower));

        if (error == 0 && liquidity == 0 && shortfall > 0) {
            console.log("liquidating");
            uint repayAmount = 1250e18;
            callBackData.cUSDC.liquidateBorrow(
                callBackData.borrower,
                repayAmount,
                CTokenInterface(address(callBackData.cUNI))
            );
        }

        //redeem cUNI to UNI
        callBackData.cUNI.redeem(callBackData.cUNI.balanceOf(address(this)));
        uint256 UNIBalance = callBackData.UNI.balanceOf(address(this));

        // approve uni
        callBackData.UNI.approve(address(UNISWAP_V3_ROUTER), UNIBalance);
        ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: callBackData.UNIAddress,
                tokenOut: callBackData.USDCAddress,
                fee: 3000, // 0.3%
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: UNIBalance,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        uint256 amountOut = ISwapRouter(UNISWAP_V3_ROUTER).exactInputSingle(
            swapParams
        );
        // repay
        callBackData.USDC.approve(address(POOL()), 1250e18 + premium);
        callBackData.USDC.transfer(callBackData.liquidator, amountOut);

        return true;
    }

    function execute(
        address _liquidator,
        address _borrower,
        address _USDCAddress,
        address _UNIAddress,
        IERC20 _USDC,
        IERC20 _UNI,
        Comptroller _unitrollerProxy,
        CErc20Delegator _cUSDC,
        CErc20Delegator _cUNI,
        CErc20Delegate _cUSDCDelegate,
        CErc20Delegate _cUNIDelegate
    ) external {
        // TODO
        CallbackData memory callbackUsed = CallbackData({
            liquidator: _liquidator,
            borrower: _borrower,
            USDCAddress: _USDCAddress,
            UNIAddress: _UNIAddress,
            USDC: _USDC,
            UNI: _UNI,
            unitrollerProxy: _unitrollerProxy,
            cUSDC: _cUSDC,
            cUNI: _cUNI,
            cUSDCDelegate: _cUSDCDelegate,
            cUNIDelegate: _cUNIDelegate
        });

        POOL().flashLoanSimple(
            address(this),
            _USDCAddress,
            1,
            abi.encode(callbackUsed),
            0
        );
    }

    function ADDRESSES_PROVIDER() public view returns (IPoolAddressesProvider) {
        return IPoolAddressesProvider(POOL_ADDRESSES_PROVIDER);
    }

    function POOL() public view returns (IPool) {
        return IPool(ADDRESSES_PROVIDER().getPool());
    }
}

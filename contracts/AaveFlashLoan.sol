pragma solidity 0.8.19;

import "forge-std/console.sol";
import "openzeppelin/token/ERC20/IERC20.sol";
import "openzeppelin/token/ERC20/ERC20.sol";
import {IFlashLoanSimpleReceiver, IPoolAddressesProvider, IPool} from "aave-v3-core/contracts/flashloan/interfaces/IFlashLoanSimpleReceiver.sol";
import {ISwapRouter} from "v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {TransferHelper} from "v3-periphery/contracts/libraries/TransferHelper.sol";

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

// TODO: Inherit IFlashLoanSimpleReceiver
contract AaveFlashLoan is IFlashLoanSimpleReceiver {
    address constant POOL_ADDRESSES_PROVIDER =
        0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;
    address UNISWAP_V3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    uint256 constant usdcAmount = 1250 * 10 ** 6;

    struct CallbackData {
        address liquidator;
        address borrower;
        address USDCAddress;
        address UNIAddress;
        IERC20 USDC;
        IERC20 UNI;
        CErc20Delegator cUSDC;
        CErc20Delegator cUNI;
        CErc20Delegate cUSDCDelegate;
        CErc20Delegate cUNIDelegate;
        Comptroller unitrollerProxy;
    }

    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external returns (bool) {
        CallbackData memory callBackData = abi.decode(params, (CallbackData));

        callBackData.USDC.approve(address(callBackData.cUSDC), usdcAmount);
        (uint error, uint liquidity, uint shortfall) = callBackData
            .unitrollerProxy
            .getAccountLiquidity(address(callBackData.borrower));

        if (error == 0 && liquidity == 0 && shortfall > 0) {
            callBackData.cUSDC.liquidateBorrow(
                callBackData.borrower,
                usdcAmount,
                CTokenInterface(address(callBackData.cUNI))
            );
        }
        // get cUNI by borrow collateral after liquidate
        // redeem cUNI to UNI
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
        callBackData.USDC.approve(address(POOL()), usdcAmount + premium);
        return true;
    }

    function execute(
        address _liquidator,
        address _borrower,
        address _USDCAddress,
        address _UNIAddress,
        IERC20 _USDC,
        IERC20 _UNI,
        CErc20Delegator _cUSDC,
        CErc20Delegator _cUNI,
        CErc20Delegate _cUSDCDelegate,
        CErc20Delegate _cUNIDelegate,
        Comptroller _unitrollerProxy
    ) external {
        // TODO
        CallbackData memory callbackData = CallbackData({
            liquidator: _liquidator,
            borrower: _borrower,
            USDCAddress: _USDCAddress,
            UNIAddress: _UNIAddress,
            USDC: _USDC,
            UNI: _UNI,
            cUSDC: _cUSDC,
            cUNI: _cUNI,
            cUSDCDelegate: _cUSDCDelegate,
            cUNIDelegate: _cUNIDelegate,
            unitrollerProxy: _unitrollerProxy
        });

        POOL().flashLoanSimple(
            address(this),
            _USDCAddress,
            usdcAmount,
            abi.encode(callbackData),
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

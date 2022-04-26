import "../lib/solmate/src/mixins/ERC4626.sol";
import "../lib/solmate/src/utils/FixedPointMathLib.sol";


interface ICVault {
    function value () external view returns (uint256);
    
}
interface IOracle {
    function getPrice() external view returns (uint256);
    function value() external view returns (uint256);
}

contract Vault is ERC4626 {
    using FixedPointMathLib for uint256;
    uint256 public RR; //Redemption Rate
    uint256 public vASSETS; //Vault Assets value (supply of vault * RR +1)
    uint256 public cASSETS; //productive Vault Shares value (value of funds earning yield)
    address public gov;
    address public cVault;
    uint256 public backing;
    address public oracle;

    struct vaultBal {
        uint256 assetsVal;
        uint256 shares;
        uint256 rate;
        uint256 buffer;
    }
    constructor(address _oracle, address _cVault, ERC20 underlying) ERC4626(underlying, "ARC", "ARCADIA"){
        gov = msg.sender;
        cVault = _cVault;
        backing = 0;
        RR = 0;
        vASSETS = 0;
        cASSETS = 0;
        RR = IOracle(_oracle).value();
        oracle = _oracle;
    }
    
    function totalAssets() public view override returns (uint256){
        uint256 total = totalSupply;
        return total.mulWadDown(RR + 1);
    }
    function cVaultValue() public view returns (uint256){
        uint256 total = ICVault(cVault).value();
        return total;
    }
    function afterDeposit(uint256 assets, uint256 shares) internal override {
        uint256 _in = shares.mulWadDown(RR + 1);
        backing += _in;
        _reBal();
    }
    function _reBal() public {
        uint256 _in = backing.mulWadDown(RR + 1);
        if(asset.balanceOf(address(this)) > _in){
            uint256 out = asset.balanceOf(address(this)) - _in;
            asset.transfer(cVault, out);
        }
         return;
    }
    function updateRR(uint256 _RR) public {
        require(gov == msg.sender, "Only gov can update RR");
        RR = _RR;
        vASSETS = totalAssets().mulWadDown(RR + 1);
        cASSETS = cVaultValue().mulWadDown(RR + 1);
        _reBal();
    }
    function testRR() public view returns (uint256){
        IOracle(oracle).value();
    }

}

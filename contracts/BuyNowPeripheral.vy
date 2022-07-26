# @version ^0.3.3


# Interfaces

from vyper.interfaces import ERC20 as IERC20
from vyper.interfaces import ERC165 as IERC165
from vyper.interfaces import ERC721 as IERC721
from interfaces import IBuyNowCore
from interfaces import ILoansCore
from interfaces import ILendingPoolPeripheral
from interfaces import ICollateralVaultPeripheral

interface INFTXVaultFactory:
    def vaultsForAsset(assetAddress: address) -> DynArray[address, 10]: view

interface INFTXVault:
    def allValidNFTs(tokenIds: uint256[1]) -> bool: view

interface ISushiRouter:
    def getAmountsOut(amountIn: uint256, path: address[2]) -> uint256[2]: view


# Structs

struct Collateral:
    contractAddress: address
    tokenId: uint256
    amount: uint256

struct Loan:
    id: uint256
    amount: uint256
    interest: uint256 # parts per 10000, e.g. 2.5% is represented by 250 parts per 10000
    maturity: uint256
    startTime: uint256
    collaterals: DynArray[Collateral, 20]
    paidAmount: uint256
    started: bool
    invalidated: bool
    paid: bool
    defaulted: bool
    canceled: bool

struct InvestorFunds:
    currentAmountDeposited: uint256
    totalAmountDeposited: uint256
    totalAmountWithdrawn: uint256
    sharesBasisPoints: uint256
    activeForRewards: bool

struct Liquidation:
    collateralAddress: address
    tokenId: uint256
    startTime: uint256
    gracePeriodMaturity: uint256
    buyNowPeriodMaturity: uint256
    principal: uint256
    interestAmount: uint256
    apr: uint256 # parts per 10000, e.g. 2.5% is represented by 250 parts per 10000
    gracePeriodPrice: uint256
    buyNowPeriodPrice: uint256
    borrower: address
    erc20TokenContract: address
    inAuction: bool


# Events

event OwnershipTransferred:
    ownerIndexed: indexed(address)
    proposedOwnerIndexed: indexed(address)
    owner: address
    proposedOwner: address

event OwnerProposed:
    ownerIndexed: indexed(address)
    proposedOwnerIndexed: indexed(address)
    owner: address
    proposedOwner: address

event GracePeriodDurationChanged:
    currentValue: uint256
    newValue: uint256

event BuyNowPeriodDurationChanged:
    currentValue: uint256
    newValue: uint256

event AuctionPeriodDurationChanged:
    currentValue: uint256
    newValue: uint256

event BuyNowCoreAddressSet:
    currentValue: address
    newValue: address

event LoansCoreAddressAdded:
    erc20TokenContractIndexed: indexed(address)
    currentValue: address
    newValue: address
    erc20TokenContract: address

event LoansCoreAddressRemoved:
    erc20TokenContractIndexed: indexed(address)
    currentValue: address
    erc20TokenContract: address

event LendingPoolPeripheralAddressAdded:
    erc20TokenContractIndexed: indexed(address)
    currentValue: address
    newValue: address
    erc20TokenContract: address

event LendingPoolPeripheralAddressRemoved:
    erc20TokenContractIndexed: indexed(address)
    currentValue: address
    erc20TokenContract: address

event CollateralVaultPeripheralAddressSet:
    currentValue: address
    newValue: address

event NFTXVaultFactoryAddressSet:
    currentValue: address
    newValue: address

event SushiRouterAddressSet:
    currentValue: address
    newValue: address

event LiquidationAdded:
    erc20TokenContractIndexed: indexed(address)
    collateralAddressIndexed: indexed(address)
    collateralAddress: address
    tokenId: uint256
    erc20TokenContract: address
    gracePeriodPrice: uint256
    buyNowPeriodPrice: uint256

event LiquidationRemoved:
    erc20TokenContractIndexed: indexed(address)
    collateralAddressIndexed: indexed(address)
    collateralAddress: address
    tokenId: uint256
    erc20TokenContract: address

event NFTPurchased:
    erc20TokenContractIndexed: indexed(address)
    collateralAddressIndexed: indexed(address)
    fromIndexed: indexed(address)
    collateralAddress: address
    tokenId: uint256
    amount: uint256
    _from: address
    erc20TokenContract: address


# Global variables

owner: public(address)
proposedOwner: public(address)

gracePeriodDuration: public(uint256)
buyNowPeriodDuration: public(uint256)
auctionPeriodDuration: public(uint256)

buyNowCoreAddress: public(address)
loansCoreAddresses: public(HashMap[address, address]) # mapping between ERC20 contract and LoansCore
lendingPoolPeripheralAddresses: public(HashMap[address, address]) # mapping between ERC20 contract and LendingPoolCore
collateralVaultPeripheralAddress: public(address)
nftxVaultFactoryAddress: public(address)
sushiRouterAddress: public(address)
wethAddress: immutable(address)

lenderMinDepositAmount: public(uint256)

##### INTERNAL METHODS #####

@view
@internal
def _daysForInterest(_liquidation: Liquidation) -> uint256:
    days: uint256 = 0
    if block.timestamp <= _liquidation.gracePeriodMaturity:
        assert msg.sender == _liquidation.borrower, "msg.sender is not borrower"
        days = 2
    elif block.timestamp <= _liquidation.buyNowPeriodMaturity:
        assert ILendingPoolPeripheral(
            self.lendingPoolPeripheralAddresses[_liquidation.erc20TokenContract]
        ).lenderFunds(msg.sender).currentAmountDeposited > self.lenderMinDepositAmount, "msg.sender is not a lender"
        days = 17
    else:
        raise "liquidation out of buying period"
    
    return days


@pure
@internal
def _computeNFTPrice(principal: uint256, interestAmount: uint256, apr: uint256, days: uint256) -> uint256:
    return principal + interestAmount + (principal * apr * days) / 365


@pure
@internal
def _computeInterestAmount(principal: uint256, interestAmount: uint256, apr: uint256, days: uint256) -> uint256:
    return interestAmount + (principal * apr * days) / 365


@view
@internal
def _getAutoLiquidationPrice(_collateralAddress: address, _tokenId: uint256) -> uint256:
    vault_addrs: DynArray[address, 10] = INFTXVaultFactory(self.nftxVaultFactoryAddress).vaultsForAsset(_collateralAddress)
    vault_addr: address = vault_addrs[len(vault_addrs) - 1]

    assert INFTXVault(vault_addr).allValidNFTs([_tokenId]), "collateral not accepted"

    amountsOut: uint256[2] = ISushiRouter(self.sushiRouterAddress).getAmountsOut(as_wei_value(0.9, "ether"), [vault_addr, wethAddress])

    return amountsOut[1]


@pure
@internal
def _isCollateralInArray(_collaterals: DynArray[Collateral, 20], _collateralAddress: address, _tokenId: uint256) -> bool:
    for collateral in _collaterals:
        if collateral.contractAddress == _collateralAddress and collateral.tokenId == _tokenId:
            return True
    return False


@pure
@internal
def _getCollateralAmount(_collaterals: DynArray[Collateral, 20], _collateralAddress: address, _tokenId: uint256) -> uint256:
    for collateral in _collaterals:
        if collateral.contractAddress == _collateralAddress and collateral.tokenId == _tokenId:
            return collateral.amount
    return MAX_UINT256


##### EXTERNAL METHODS - VIEW #####

@view
@external
def getLiquidation(_collateralAddress: address, _tokenId: uint256) -> Liquidation:
    return IBuyNowCore(self.buyNowCoreAddress).getLiquidation(_collateralAddress, _tokenId)


##### EXTERNAL METHODS - WRITE #####
@external
def __init__(_buyNowCoreAddress: address, _gracePeriodDuration: uint256, _buyNowPeriodDuration: uint256, _auctionPeriodDuration: uint256, _wethAddress: address):
    assert _buyNowCoreAddress != ZERO_ADDRESS, "address is the zero address"
    assert _buyNowCoreAddress.is_contract, "address is not a contract"
    assert _wethAddress != ZERO_ADDRESS, "address is the zero address"
    assert _wethAddress.is_contract, "address is not a contract"
    assert _gracePeriodDuration > 0, "duration is 0"
    assert _buyNowPeriodDuration > 0, "duration is 0"
    assert _auctionPeriodDuration > 0, "duration is 0"

    self.owner = msg.sender
    self.buyNowCoreAddress = _buyNowCoreAddress
    self.gracePeriodDuration = _gracePeriodDuration
    self.buyNowPeriodDuration = _buyNowPeriodDuration
    self.auctionPeriodDuration = _auctionPeriodDuration
    wethAddress = _wethAddress


@external
def proposeOwner(_address: address):
    assert msg.sender == self.owner, "msg.sender is not the owner"
    assert _address != ZERO_ADDRESS, "address it the zero address"
    assert self.owner != _address, "proposed owner addr is the owner"
    assert self.proposedOwner != _address, "proposed owner addr is the same"

    self.proposedOwner = _address

    log OwnerProposed(
        self.owner,
        _address,
        self.owner,
        _address,
    )


@external
def claimOwnership():
    assert msg.sender == self.proposedOwner, "msg.sender is not the proposed"

    log OwnershipTransferred(
        self.owner,
        self.proposedOwner,
        self.owner,
        self.proposedOwner,
    )

    self.owner = self.proposedOwner
    self.proposedOwner = ZERO_ADDRESS


@external
def setGracePeriodDuration(_duration: uint256):
    assert msg.sender == self.owner, "msg.sender is not the owner"
    assert _duration > 0, "duration is 0"
    assert _duration != self.gracePeriodDuration, "new value is the same"

    log GracePeriodDurationChanged(
        self.gracePeriodDuration,
        _duration
    )

    self.gracePeriodDuration = _duration


@external
def setBuyNowPeriodDuration(_duration: uint256):
    assert msg.sender == self.owner, "msg.sender is not the owner"
    assert _duration > 0, "duration is 0"
    assert _duration != self.buyNowPeriodDuration, "new value is the same"

    log BuyNowPeriodDurationChanged(
        self.buyNowPeriodDuration,
        _duration
    )

    self.buyNowPeriodDuration = _duration


@external
def setAuctionPeriodDuration(_duration: uint256):
    assert msg.sender == self.owner, "msg.sender is not the owner"
    assert _duration > 0, "duration is 0"
    assert _duration != self.auctionPeriodDuration, "new value is the same"

    log AuctionPeriodDurationChanged(
        self.auctionPeriodDuration,
        _duration
    )

    self.auctionPeriodDuration = _duration


@external
def setBuyNowCoreAddress(_address: address):
    assert msg.sender == self.owner, "msg.sender is not the owner"
    assert _address != ZERO_ADDRESS, "address is the zero addr"
    assert _address.is_contract, "address is not a contract"
    assert self.buyNowCoreAddress != _address, "new value is the same"

    log BuyNowCoreAddressSet(
        self.buyNowCoreAddress,
        _address,
    )

    self.buyNowCoreAddress = _address


@external
def addLoansCoreAddress(_erc20TokenContract: address, _address: address):
    assert msg.sender == self.owner, "msg.sender is not the owner"
    assert _address != ZERO_ADDRESS, "address is the zero addr"
    assert _address.is_contract, "address is not a contract"
    assert _erc20TokenContract != ZERO_ADDRESS, "erc20TokenAddr is the zero addr"
    assert _erc20TokenContract.is_contract, "erc20TokenAddr is not a contract"
    assert self.loansCoreAddresses[_erc20TokenContract] != _address, "new value is the same"

    log LoansCoreAddressAdded(
        _erc20TokenContract,
        self.loansCoreAddresses[_erc20TokenContract],
        _address,
        _erc20TokenContract
    )

    self.loansCoreAddresses[_erc20TokenContract] = _address


@external
def removeLoansCoreAddress(_erc20TokenContract: address):
    assert msg.sender == self.owner, "msg.sender is not the owner"
    assert _erc20TokenContract != ZERO_ADDRESS, "erc20TokenAddr is the zero addr"
    assert _erc20TokenContract.is_contract, "erc20TokenAddr is not a contract"
    assert self.loansCoreAddresses[_erc20TokenContract] != ZERO_ADDRESS, "address not found"

    log LoansCoreAddressRemoved(
        _erc20TokenContract,
        self.loansCoreAddresses[_erc20TokenContract],
        _erc20TokenContract
    )

    self.loansCoreAddresses[_erc20TokenContract] = ZERO_ADDRESS


@external
def addLendingPoolPeripheralAddress(_erc20TokenContract: address, _address: address):
    assert msg.sender == self.owner, "msg.sender is not the owner"
    assert _address != ZERO_ADDRESS, "address is the zero addr"
    assert _address.is_contract, "address is not a contract"
    assert _erc20TokenContract != ZERO_ADDRESS, "erc20TokenAddr is the zero addr"
    assert _erc20TokenContract.is_contract, "erc20TokenAddr is not a contract"
    assert self.lendingPoolPeripheralAddresses[_erc20TokenContract] != _address, "new value is the same"

    log LendingPoolPeripheralAddressAdded(
        _erc20TokenContract,
        self.lendingPoolPeripheralAddresses[_erc20TokenContract],
        _address,
        _erc20TokenContract
    )

    self.lendingPoolPeripheralAddresses[_erc20TokenContract] = _address


@external
def removeLendingPoolPeripheralAddress(_erc20TokenContract: address):
    assert msg.sender == self.owner, "msg.sender is not the owner"
    assert _erc20TokenContract != ZERO_ADDRESS, "erc20TokenAddr is the zero addr"
    assert _erc20TokenContract.is_contract, "erc20TokenAddr is not a contract"
    assert self.lendingPoolPeripheralAddresses[_erc20TokenContract] != ZERO_ADDRESS, "address not found"

    log LendingPoolPeripheralAddressRemoved(
        _erc20TokenContract,
        self.lendingPoolPeripheralAddresses[_erc20TokenContract],
        _erc20TokenContract
    )

    self.lendingPoolPeripheralAddresses[_erc20TokenContract] = ZERO_ADDRESS


@external
def setCollateralVaultPeripheralAddress(_address: address):
    assert msg.sender == self.owner, "msg.sender is not the owner"
    assert _address != ZERO_ADDRESS, "address is the zero addr"
    assert self.collateralVaultPeripheralAddress != _address, "new value is the same"

    log CollateralVaultPeripheralAddressSet(
        self.collateralVaultPeripheralAddress,
        _address
    )

    self.collateralVaultPeripheralAddress = _address


@external
def setNFTXVaultFactoryAddress(_address: address):
    assert msg.sender == self.owner, "msg.sender is not the owner"
    assert _address != ZERO_ADDRESS, "address is the zero addr"
    assert self.nftxVaultFactoryAddress != _address, "new value is the same"

    log NFTXVaultFactoryAddressSet(
        self.nftxVaultFactoryAddress,
        _address
    )

    self.nftxVaultFactoryAddress = _address


@external
def setSushiRouterAddress(_address: address):
    assert msg.sender == self.owner, "msg.sender is not the owner"
    assert _address != ZERO_ADDRESS, "address is the zero addr"
    assert self.sushiRouterAddress != _address, "new value is the same"

    log SushiRouterAddressSet(
        self.sushiRouterAddress,
        _address
    )

    self.sushiRouterAddress = _address


@external
def addLiquidation(
    _collateralAddress: address,
    _tokenId: uint256,
    _borrower: address,
    _loanId: uint256,
    _erc20TokenContract: address
):
    assert IERC721(_collateralAddress).ownerOf(_tokenId) == ICollateralVaultPeripheral(self.collateralVaultPeripheralAddress).collateralVaultCoreAddress(), "collateral not owned by vault"
    
    borrowerLoan: Loan = ILoansCore(self.loansCoreAddresses[_erc20TokenContract]).getLoan(_borrower, _loanId)
    assert borrowerLoan.defaulted, "loan is not defaulted"
    assert self._isCollateralInArray(borrowerLoan.collaterals, _collateralAddress, _tokenId), "collateral not in loan"

    principal: uint256 = self._getCollateralAmount(borrowerLoan.collaterals, _collateralAddress, _tokenId)
    interestAmount: uint256 = principal * (10000 + borrowerLoan.interest) / 10000
    # # APR from loan duration (maturity)
    apr: uint256 = borrowerLoan.interest * 31536000 / (borrowerLoan.maturity - borrowerLoan.startTime)

    gracePeriodPrice: uint256 = self._computeNFTPrice(principal, interestAmount, apr, 2)
    protocolPrice: uint256 = self._computeNFTPrice(principal, interestAmount, apr, 17)
    # autoLiquidationPrice: uint256 = self._getAutoLiquidationPrice(_collateralAddress, _tokenId)
    autoLiquidationPrice: uint256 = 0
    buyNowPeriodPrice: uint256 = 0
    
    if protocolPrice > autoLiquidationPrice:
        buyNowPeriodPrice = protocolPrice
    else:
        buyNowPeriodPrice = autoLiquidationPrice


    IBuyNowCore(self.buyNowCoreAddress).addLiquidation(
        _collateralAddress,
        _tokenId,
        block.timestamp,
        block.timestamp + self.gracePeriodDuration,
        block.timestamp + self.gracePeriodDuration + self.buyNowPeriodDuration,
        principal,
        interestAmount,
        apr,
        gracePeriodPrice,
        buyNowPeriodPrice,
        _borrower,
        _erc20TokenContract
    )

    log LiquidationAdded(
        _erc20TokenContract,
        _collateralAddress,
        _collateralAddress,
        _tokenId,
        _erc20TokenContract,
        gracePeriodPrice,
        buyNowPeriodPrice
    )


# @external
# def buyNFT(_collateralAddress: address, _tokenId: uint256):
#     assert _collateralAddress != ZERO_ADDRESS, "collat addr is the zero addr"
#     assert _collateralAddress.is_contract, "collat addr is not a contract"
#     assert IERC165(_collateralAddress).supportsInterface(0x80ac58cd), "collat addr is not a ERC721"
#     assert IERC721(_collateralAddress).ownerOf(_tokenId) == ICollateralVaultPeripheral(self.collateralVaultPeripheralAddress).collateralVaultCoreAddress(), "collateral not owned by vault"

#     liquidation: Liquidation = IBuyNowCore(self.buyNowCoreAddress).getLiquidation(_collateralAddress, _tokenId)

#     assert not liquidation.inAuction, "liquidation is in auction"

#     # days: uint256 = 0
#     # if block.timestamp <= liquidation.gracePeriodMaturity:
#     #     assert msg.sender == liquidation.borrower, "msg.sender is not borrower"
#     #     days = 2
#     # elif block.timestamp <= liquidation.buyNowPeriodMaturity:
#     #     assert ILendingPoolPeripheral(
#     #         self.lendingPoolPeripheralAddresses[liquidation.erc20TokenContract]
#     #     ).lenderFunds(msg.sender).currentAmountDeposited > self.lenderMinDepositAmount, "msg.sender is not a lender"
#     #     days = 17
#     # else:
#     #     raise "liquidation out of buying period"
    
#     days: uint256 = self._daysForInterest(liquidation)

#     # nftPrice: uint256 = self._computeNFTPrice(liquidation.principal, liquidation.interestAmount, liquidation.apr, days)

#     IBuyNowCore(self.buyNowCoreAddress).removeLiquidation(_collateralAddress, _tokenId)

#     log LiquidationRemoved(
#         liquidation.erc20TokenContract,
#         liquidation.collateralAddress,
#         liquidation.collateralAddress,
#         liquidation.tokenId,
#         liquidation.erc20TokenContract
#     )

#     ILendingPoolPeripheral(self.lendingPoolPeripheralAddresses[liquidation.erc20TokenContract]).receiveFundsFromLiquidation(
#         msg.sender,
#         liquidation.principal,
#         self._computeInterestAmount(liquidation.principal, liquidation.interestAmount, liquidation.apr, days)
#     )

#     ICollateralVaultPeripheral(self.collateralVaultPeripheralAddress).transferCollateralFromLiquidation(msg.sender, _collateralAddress, _tokenId)

#     log NFTPurchased(
#         liquidation.erc20TokenContract,
#         _collateralAddress,
#         msg.sender,
#         _collateralAddress,
#         _tokenId,
#         self._computeNFTPrice(liquidation.principal, liquidation.interestAmount, liquidation.apr, days),
#         msg.sender,
#         liquidation.erc20TokenContract
#     )


@external
def buyNFTGracePeriod(_collateralAddress: address, _tokenId: uint256):
    assert IERC721(_collateralAddress).ownerOf(_tokenId) == ICollateralVaultPeripheral(self.collateralVaultPeripheralAddress).collateralVaultCoreAddress(), "collateral not owned by vault"
    assert block.timestamp <= IBuyNowCore(self.buyNowCoreAddress).getLiquidationGracePeriodMaturity(_collateralAddress, _tokenId), "liquidation out of grace period"
    assert msg.sender == IBuyNowCore(self.buyNowCoreAddress).getLiquidationBorrower(_collateralAddress, _tokenId), "msg.sender is not borrower"
    assert not IBuyNowCore(self.buyNowCoreAddress).isLiquidationInAuction(_collateralAddress, _tokenId), "liquidation is in auction"

    liquidation: Liquidation = IBuyNowCore(self.buyNowCoreAddress).getLiquidation(_collateralAddress, _tokenId)

    IBuyNowCore(self.buyNowCoreAddress).removeLiquidation(_collateralAddress, _tokenId)

    log LiquidationRemoved(
        liquidation.erc20TokenContract,
        liquidation.collateralAddress,
        liquidation.collateralAddress,
        liquidation.tokenId,
        liquidation.erc20TokenContract
    )

    ILendingPoolPeripheral(self.lendingPoolPeripheralAddresses[liquidation.erc20TokenContract]).receiveFundsFromLiquidation(
        msg.sender,
        liquidation.principal,
        self._computeInterestAmount(liquidation.principal, liquidation.interestAmount, liquidation.apr, 2)
    )

    ICollateralVaultPeripheral(self.collateralVaultPeripheralAddress).transferCollateralFromLiquidation(msg.sender, _collateralAddress, _tokenId)

    log NFTPurchased(
        liquidation.erc20TokenContract,
        _collateralAddress,
        msg.sender,
        _collateralAddress,
        _tokenId,
        self._computeNFTPrice(liquidation.principal, liquidation.interestAmount, liquidation.apr, 2),
        msg.sender,
        liquidation.erc20TokenContract
    )


@external
def buyNFTBuyNowPeriod(_collateralAddress: address, _tokenId: uint256):
    assert _collateralAddress != ZERO_ADDRESS, "collat addr is the zero addr"
    assert _collateralAddress.is_contract, "collat addr is not a contract"
    assert IERC165(_collateralAddress).supportsInterface(0x80ac58cd), "collat addr is not a ERC721"
    assert IERC721(_collateralAddress).ownerOf(_tokenId) == ICollateralVaultPeripheral(self.collateralVaultPeripheralAddress).collateralVaultCoreAddress(), "collateral not owned by vault"
    assert block.timestamp > IBuyNowCore(self.buyNowCoreAddress).getLiquidationGracePeriodMaturity(_collateralAddress, _tokenId), "liquidation in grace period"
    assert block.timestamp <= IBuyNowCore(self.buyNowCoreAddress).getLiquidationBuyNowPeriodMaturity(_collateralAddress, _tokenId), "liquidation out of buynow period"
    assert not IBuyNowCore(self.buyNowCoreAddress).isLiquidationInAuction(_collateralAddress, _tokenId), "liquidation is in auction"

    liquidation: Liquidation = IBuyNowCore(self.buyNowCoreAddress).getLiquidation(_collateralAddress, _tokenId)
    protocolPrice: uint256 = self._computeNFTPrice(liquidation.principal, liquidation.interestAmount, liquidation.apr, 17)
    autoLiquidationPrice: uint256 = self._getAutoLiquidationPrice(_collateralAddress, _tokenId)
    nftPrice: uint256 = 0
    
    if protocolPrice > autoLiquidationPrice:
        nftPrice = protocolPrice
    else:
        nftPrice = autoLiquidationPrice

    IBuyNowCore(self.buyNowCoreAddress).removeLiquidation(_collateralAddress, _tokenId)

    log LiquidationRemoved(
        liquidation.erc20TokenContract,
        liquidation.collateralAddress,
        liquidation.collateralAddress,
        liquidation.tokenId,
        liquidation.erc20TokenContract
    )

    ILendingPoolPeripheral(self.lendingPoolPeripheralAddresses[liquidation.erc20TokenContract]).receiveFundsFromLiquidation(
        msg.sender,
        liquidation.principal,
        nftPrice
    )

    ICollateralVaultPeripheral(self.collateralVaultPeripheralAddress).transferCollateralFromLiquidation(msg.sender, _collateralAddress, _tokenId)

    log NFTPurchased(
        liquidation.erc20TokenContract,
        _collateralAddress,
        msg.sender,
        _collateralAddress,
        _tokenId,
        nftPrice,
        msg.sender,
        liquidation.erc20TokenContract
    )


@external
def liquidateNFTX():
    pass


@external
def liquidateOpenSea():
    pass




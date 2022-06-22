# Structs

struct InvestorFunds:
    currentAmountDeposited: uint256
    totalAmountDeposited: uint256
    totalAmountWithdrawn: uint256
    sharesBasisPoints: uint256
    activeForRewards: bool

# Events

event OwnershipTransferred:
    ownerIndexed: address
    proposedOwnerIndexed: address
    owner: address
    proposedOwner: address
    erc20TokenContract: address
event Deposit:
    walletIndexed: address
    wallet: address
    amount: uint256
    erc20TokenContract: address
event Withdrawal:
    walletIndexed: address
    wallet: address
    amount: uint256
    erc20TokenContract: address
event FundsTransfer:
    walletIndexed: address
    wallet: address
    amount: uint256
    erc20TokenContract: address
event FundsReceipt:
    walletIndexed: address
    wallet: address
    amount: uint256
    rewardsPool: uint256
    rewardsProtocol: uint256
    erc20TokenContract: address

# Functions

@view
@external
def maxFundsInvestable() -> uint256:
    pass

@external
def proposeOwner(_address: address):
    pass

@external
def claimOwnership():
    pass

@external
def changeMaxCapitalEfficiency(_value: uint256):
    pass

@external
def changeProtocolWallet(_address: address):
    pass

@external
def changeProtocolFeesShare(_value: uint256):
    pass

@external
def changePoolStatus(_flag: bool):
    pass

@external
def setLoansPeripheralAddress(_address: address):
    pass

@external
def deprecate():
    pass

@external
def changeWhitelistStatus(_flag: bool):
    pass

@external
def addWhitelistedAddress(_address: address):
    pass

@external
def removeWhitelistedAddress(_address: address):
    pass

@external
def deposit(_amount: uint256):
    pass

@external
def withdraw(_amount: uint256):
    pass

@external
def sendFunds(_to: address, _amount: uint256):
    pass

@external
def receiveFunds(_borrower: address, _amount: uint256, _rewardsAmount: uint256):
    pass

@view
@external
def owner() -> address:
    pass

@view
@external
def proposedOwner() -> address:
    pass

@view
@external
def loansContract() -> address:
    pass

@view
@external
def lendingPoolCoreContract() -> address:
    pass

@view
@external
def erc20TokenContract() -> address:
    pass

@view
@external
def protocolWallet() -> address:
    pass

@view
@external
def protocolFeesShare() -> uint256:
    pass

@view
@external
def maxCapitalEfficienty() -> uint256:
    pass

@view
@external
def isPoolActive() -> bool:
    pass

@view
@external
def isPoolDeprecated() -> bool:
    pass

@view
@external
def isPoolInvesting() -> bool:
    pass

@view
@external
def whitelistEnabled() -> bool:
    pass

@view
@external
def whitelistedAddresses(arg0: address) -> bool:
    pass



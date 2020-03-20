/**

    The software and documentation available in this repository (the "Software") is
    protected by copyright law and accessible pursuant to the license set forth below.

    Copyright © 2019 Staked Securely, Inc. All rights reserved.

    Permission is hereby granted, free of charge, to any person or organization
    obtaining the Software (the “Licensee”) to privately study, review, and analyze
    the Software. Licensee shall not use the Software for any other purpose. Licensee
    shall not modify, transfer, assign, share, or sub-license the Software or any
    derivative works of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
    INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
    PARTICULAR PURPOSE, TITLE, AND NON-INFRINGEMENT. IN NO EVENT SHALL THE COPYRIGHT
    HOLDERS BE LIABLE FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT,
    OR OTHERWISE, ARISING FROM, OUT OF, OR IN CONNECTION WITH THE SOFTWARE.

*/

pragma solidity 0.4.25;
pragma experimental ABIEncoderV2;


// external dependency
import "../../../external/ddex/Action.sol";
import "../openzeppelin/ERC20/ERC20.sol";

// internal dependency
import "../../interfaces/Opportunity.sol";
import "../../interfaces/MarketByContract.sol";

import "../Storage.sol";


/// @notice  Communicating Proxy to the Hydro Protocol
///
/// @dev     Follows the standard 'Opportunity' interface
///
/// Author:  Radar Bear
/// Version: 1.0.0


contract HydroOpportunity is Opportunity, MarketByContract {


  /*************** STORAGE VARIABLE DECLARATIONS **************/


  // contracts used, this is how to dynamically reference RAY contracts from RAY Storage
  bytes32 internal constant ADMIN_CONTRACT = keccak256("AdminContract");
  bytes32 internal constant OPPORTUNITY_MANAGER_CONTRACT = keccak256("OpportunityManagerContract");

  address _ddex;
  mapping(address => address) public tokenIdentifier;


  /*************** EVENT DECLARATIONS **************/

  /*************** MODIFIER DECLARATIONS **************/


  /// @notice  Checks the caller is our Governance Wallet
  ///
  /// @dev     To be removed once fallbacks are
  modifier onlyGovernance()
  {
      require(
          msg.sender == _storage.getGovernanceWallet(),
          "#DdexImpl onlyGovernance Modifier: Only Governance can call this"
      );

      _;
  }


  /// @notice  Checks the caller is our Admin contract
  modifier onlyAdmin()
  {
      require(
          msg.sender == _storage.getContractAddress(ADMIN_CONTRACT),
          "#DdexImpl onlyAdmin Modifier: Only Admin can call this"
      );

      _;
  }

  /// @notice  Checks the caller is our OpportunityManager contract
  modifier onlyOpportunityManager()
  {
      require(
          msg.sender == _storage.getContractAddress(OPPORTUNITY_MANAGER_CONTRACT),
          "#DdexImpl onlyOpportunityManager Modifier: Only OpportunityManager can call this"
      );

      _;
  }

  /////////////////////// FUNCTION DECLARATIONS BEGIN ///////////////////////


  /// @notice  Sets Storage instance and inits the coins supported by the Opp.
  ///
  /// @param   __storage - The Storage contracts address
  /// @param   __ddexAddress - ddex contracts address

  constructor(
    address __storage,
    address __ddexAddress
  )
    public
  {
    storage = Storage(__storage);
    hydro = __ddexAddress;
  }


  /// @notice  Fallback function to receive Ether
  ///
  /// @dev     Required to receive Ether from Ddex upon withdrawals
  function() external payable {

  }


  /** --------------- OpportunityManager ENTRYPOINTS ----------------- **/


  /// @notice  The entrypoint for OpportunityManager to lend
  ///
  /// @param    principalToken - The coin address to lend
  /// @param    value - The amount to lend
  function supply(
    address principalToken,
    uint value,
    bool isERC20
  )
    external
    onlyOpportunityManager
    payable
  {

    address tokenAddress = tokenIdentifier[principalToken];
    uint256 sendEth;

    if (isERC20) {
      require(
        IERC20(principalToken).approve(hydro, value),
        "HydroImpl supply(): APPROVE_ERC20_FAILED"
      );
      sendEth = 0;
    } else {
      require(
        msg.value == value, 
        "HydroImpl supply(): MSG_VALUE_NOT_MATCH"
      );
      sendEth = msg.value
    }

    Action memory action;
    action.ActionType = ActionType.Supply;
    action.encodedParams = abi.encode(tokenAddress, uint256(value));
    Action[] memory actions = new Action[](1);
    actions[0] = action;

    // hydro batch doesn't return anything and reverts on error
    IHydro(_hydro).batch.value(sendEth)(actions);
  }

  /// @notice  The entrypoint for OpportunityManager to withdraw
  ///
  /// @param    principalToken - The coin address to withdraw
  /// @param    beneficiary - The address to send funds too - always OpportunityManager for now
  /// @param    valueToWithdraw - The amount to withdraw
  function withdraw(
    address principalToken,
    address beneficiary,
    uint valueToWithdraw,
    bool isERC20
  )
    external
    onlyOpportunityManager
  {

    require(
      getBalance(address principalToken)<valueToWithdraw,
      "HydroImpl withdraw(): Balance not enough"
    );

    address tokenAddress = tokenIdentifier[principalToken];    

    Action memory action;
    action.ActionType = ActionType.Unsupply;
    action.encodedParams = abi.encode(tokenAddress, uint256(value));
    Action[] memory actions = new Action[](1);
    actions[0] = action;

    IHydro(_hydro).batch(actions);

    if (isERC20) {
      require(
        IERC20(principalToken).transfer(beneficiary, valueToWithdraw),
        "HydroImpl withdraw(): Transfer of ERC20 Token failed"
      );
    } else {
      beneficiary.transfer(valueToWithdraw);
    }

  }


  /** ----------------- ONLY ADMIN MUTATORS ----------------- **/


  /// @notice  Add support for a coin
  ///
  /// @dev     This is configured in-contract since it's not common across Opportunities
  ///
  /// @param   principalTokens - The coin contract addresses
  /// @param   ddexTokenId - The token id on ddex platform contracts
  /// ddex use token address to identify erc20 tokens
  /// while 0x000000000000000000000000000000000000000E for Ether
  function addPrincipalTokens(
    address[] memory principalTokens,
    address[] memory ddexTokenId
  )
    public // not using external b/c use memory to pass in array
    onlyAdmin
  {

    for (uint i = 0; i < principalTokens.length; i++) {

      tokenIdentifier[principalTokens[i]] = ddexTokenId[i];

    }

  }

  /** ----------------- VIEW ACCESSORS ----------------- **/


  /// @notice  Get the current balance we have in the Opp. (principal + interest generated)
  ///
  /// @param   principalToken - The coins address
  ///
  /// @return  The total balance in the smallest units of the coin
  function getBalance(address principalToken) external view returns(uint) {

    address tokenAddress = tokenIdentifier[principalToken]; 
    return IHydro(_hydro).getAmountSupplied(tokenAddress, this)

  }

}
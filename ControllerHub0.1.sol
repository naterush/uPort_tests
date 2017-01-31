pragma solidity ^0.4.4;
contract Proxy {
    address masterContract = msg.sender;
    modifier onlyMaster () { if (msg.sender == masterContract) {_;}}
    function () payable{}
    function transfer (address _newMaster) onlyMaster {masterContract = _newMaster;}
    function forward(address destination, uint value, bytes data) onlyMaster payable {
    	// If a contract tries to CALL or CREATE a contract with either
    	// (i) insufficient balance, or (ii) stack depth already at maximum (1024),
    	// the sub-execution and transfer do not occur at all, no gas gets consumed, and 0 is added to the stack.
    	// see: https://github.com/ethereum/wiki/wiki/Subtleties#exceptional-conditions
        if (!destination.call.value(value)(data)) {
            throw;
        }
    }
}

contract ProxyHub {
    uint    public version;
    struct Identity {
        address userKey;
        address proposedUserKey;
        uint    proposedUserKeyPendingUntil;

        address recoveryKey;
        address proposedRecoveryKey;
        uint    proposedRecoveryKeyPendingUntil;

        address proposedController; //in the standard case, the controller is this proxy hub
        uint    proposedControllerPendingUntil;

        uint    shortTimeLock;// use 900 for 15 minutes
        uint    longTimeLock; // use 259200 for 3 days

        Proxy   proxy;
    }

    mapping (address => Identity) public identities; //routes UserKey to Identity struct

    //should index specific things
    event IdentityCreationEvent(address identityCreator, address indexed IdentityCreated);
    event RecoveryEvent(string action, address initiatedBy);
    event Forwarded(address indexed proxyAddress);


    function ProxyHub () {
        version = 1;
    }

    function createIdentity(address _userKey, address _recoveryKey, uint _shortTimeLock, uint _longTimeLock) {
        if (identities[_userKey].userKey != 0x0) throw; //make sure identity does not exist
        identities[_userKey].userKey = _userKey; //index at _userKey and not msg.sender so can have identity factory
        identities[_userKey].recoveryKey = _recoveryKey;
        identities[_userKey].shortTimeLock = _shortTimeLock;
        identities[_userKey].longTimeLock = _longTimeLock;
        Proxy proxy = new Proxy();
        identities[_userKey].proxy = proxy;
        //should this event be (_userKey, proxy) or (msg.sender, proxy)?
        IdentityCreationEvent(msg.sender, proxy);
    }

    //might make sense to have a modifier called existingIdentity - just make sure
    //a msg.sender is linked to an identity

    function forward(address destination, uint value, bytes data) {
        identities[msg.sender].proxy.forward(destination, value, data);
        Forwarded(identities[msg.sender].proxy);
  }

    function signRecoveryChange(address _proposedRecoveryKey) {
        identities[msg.sender].proposedRecoveryKeyPendingUntil = now + identities[msg.sender].longTimeLock;
        identities[msg.sender].proposedRecoveryKey = _proposedRecoveryKey;
        RecoveryEvent("signRecoveryChange", msg.sender);
    }
    function changeRecovery() {
        if(identities[msg.sender].proposedRecoveryKeyPendingUntil < now && identities[msg.sender].proposedRecoveryKey != 0x0){
            identities[msg.sender].recoveryKey = identities[msg.sender].proposedRecoveryKey;
            delete identities[msg.sender].proposedRecoveryKey;
        }
    }

    //pass 0x0 to cancel
    function signControllerChange(address _proposedController) {
        identities[msg.sender].proposedControllerPendingUntil = now + identities[msg.sender].longTimeLock;
        identities[msg.sender].proposedController = _proposedController;
        RecoveryEvent("signControllerChange", msg.sender);
    }

    function changeController() {
        if(identities[msg.sender].proposedControllerPendingUntil < now && identities[msg.sender].proposedController != 0x0){
            identities[msg.sender].proxy.transfer(identities[msg.sender].proposedController);
            delete identities[msg.sender];
            //RecoveryEvent()
        }
    }

    function updateMapping(address _oldUserKey, address _newUserKeyToMap) internal {
        if (identities[ _newUserKeyToMap].userKey != 0x0) throw; //make sure identity does not exist
        identities[_newUserKeyToMap].userKey = identities[_oldUserKey].userKey;
        identities[_newUserKeyToMap].recoveryKey = identities[_oldUserKey].recoveryKey;
        identities[_newUserKeyToMap].shortTimeLock = identities[_oldUserKey].shortTimeLock;
        identities[_newUserKeyToMap].longTimeLock = identities[_oldUserKey].longTimeLock;
        identities[_newUserKeyToMap].proxy = identities[_oldUserKey].proxy;
        delete identities[_oldUserKey];
        //recovery event
    }
    //pass 0x0 to cancel
    function signUserKeyChange(address _proposedUserKey) {
        identities[msg.sender].proposedUserKeyPendingUntil = now + identities[msg.sender].shortTimeLock;
        identities[msg.sender].proposedUserKey = _proposedUserKey;
        RecoveryEvent("signUserKeyChange", msg.sender);
    }

    function changeUserKey(){
        if(identities[msg.sender].proposedUserKeyPendingUntil < now && identities[msg.sender].proposedUserKey != 0x0){
            updateMapping(msg.sender, identities[msg.sender].proposedUserKey);
            RecoveryEvent("changeUserKey", msg.sender);
        }
    }

    modifier onlyRecoveryOfUserKey (address _claimedUserKey) {if (identities[_claimedUserKey].recoveryKey == msg.sender) { _;}}

    //claimed user key is what recovery contract is claiming it has control over
    function changeRecoveryFromRecovery(address _claimedUserKey, address _newRecoveryKey) onlyRecoveryOfUserKey(_claimedUserKey) {
        identities[_claimedUserKey].recoveryKey = _newRecoveryKey;
        //RecoveryEvent
    }

    function changeUserKeyFromRecovery(address _claimedUserKey, address _newUserKey) onlyRecoveryOfUserKey(_claimedUserKey){
        updateMapping(_claimedUserKey, _newUserKey);
        //RecoveryEvent
    }



}

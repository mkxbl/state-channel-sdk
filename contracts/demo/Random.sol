pragma solidity ^0.5.0;

import "./IRandom.sol";
import "../lib/ECDSA.sol";

/**
 * @notice Off-chain random generate algorithm
 */
contract Random is IRandom {
    using ECDSA for bytes32;

    /* States */
    uint settleWindow;
    struct Result {
        // 0 = nobody commit proof
        // 1 = acceptor had committed proof, waiting for initiator to reveal pre-image
        // 2 = all commit proof, random was generated sucessfully
        uint status;
        address initiator;
        address acceptor;
        bytes32 iRandomHash;
        bytes32 aRandom;
        bytes32 random;
        // After acceptor had committed proof, this value represents the block number before which initiator should reveal pre-image
        uint settleBlock;
    }
    // randomID => result
    mapping(bytes32 => Result) public resultMap;

    /* Constuctor */
    constructor(uint _settleWindow) public {
        settleWindow = _settleWindow;
    }

    /* Events */
    event InitiatorCommitProof(bytes32 indexed randomID, address indexed initiator, address indexed acceptor, bytes32 random);

    event AcceptorCommitProof(bytes32 indexed randomID, address indexed initiator, address indexed acceptor, uint settleBlock);

    event InitiatorReveal(bytes32 indexed randomID, bytes32 random);

    /* External Functions */
    /**
     * @notice Called by other contracts to get random
     * @param randomID id of random generation
     * @param initiator address of peer who initiate  random generation
     * @param acceptor address of the other peer who accept random generation
     * @return (status, random, winner if random generation failed)
     */
    function getRandom(bytes32 randomID, address initiator, address acceptor) external returns(uint, bytes32, address){
        Result storage result = resultMap[randomID];
        if(result.status == 0) {
            return (0, bytes32(0), address(0));
        } else if(result.status == 1) {
            require(block.number > result.settleBlock, "waiting initiator to reveal pre-image");
            return (1, bytes32(0), acceptor);
        } else if(result.status == 2) {
            return (2, result.random, address(0));
        }
    }

    /* Public Functions */
    /**
     * @notice Commit proof to generate random on-chain when dispute off-chain
     * @param randomID id of this random round
     * @param initiator address of peer who initiate  random generation
     * @param acceptor address of the other peer who accept random generation
     * @param iRandomHash hash of initiator pre-image
     * @param iSig signature of initiator
     * @param aRandom pre-image of acceptor
     * @param aSig signature of acceptor
     * @param iRandom pre-image of initiator
     */
    function initiatorCommitProof(bytes32 randomID, address initiator, address acceptor, bytes32 iRandomHash, bytes memory iSig, bytes32 aRandom, bytes memory aSig, bytes32 iRandom) public {
        verifyProof(randomID, initiator, acceptor, iRandomHash, iSig, aRandom, aSig);
        require(keccak256(abi.encodePacked(iRandom)) == iRandomHash, "invalid pre-image of initiator random hash");
        Result storage result = resultMap[randomID];
        require(result.status == 0, "already committed");
        result.status = 2;
        result.random = keccak256(abi.encodePacked(iRandom, aRandom));
        emit InitiatorCommitProof(randomID, initiator, acceptor, result.random);
    }

    /**
     * @notice Commit proof to generate random on-chain when dispute off-chain
     * @param randomID id of this random round
     * @param initiator address of peer who initiate  random generation
     * @param acceptor address of the other peer who accept random generation
     * @param iRandomHash hash of initiator pre-image
     * @param iSig signature of initiator
     * @param aRandom pre-image of acceptor
     * @param aSig signature of acceptor
     */
    function acceptorCommitProof(bytes32 randomID, address initiator, address acceptor, bytes32 iRandomHash, bytes memory iSig, bytes32 aRandom, bytes memory aSig) public {
        verifyProof(randomID, initiator, acceptor, iRandomHash, iSig, aRandom, aSig);
        Result storage result = resultMap[randomID];
        require(result.status == 0, "already committed");
        result.status = 1;
        result.initiator = initiator;
        result.acceptor = acceptor;
        result.iRandomHash = iRandomHash;
        result.aRandom = aRandom;
        result.settleBlock = settleWindow + block.number;
        emit AcceptorCommitProof(randomID, initiator, acceptor, result.settleBlock);
    }

    /**
     * @notice initiator reveal pre-image after acceptor commit proof
     * @param randomID id of this random round
     * @param iRandom pre-image of initiator
     */
    function initiatorReveal(bytes32 randomID, bytes32 iRandom) public {
        Result storage result = resultMap[randomID];
        require(result.status == 1, "invalid status");
        require(block.number <= result.settleBlock, "reveal block expired");
        require(keccak256(abi.encodePacked(iRandom)) == result.iRandomHash, "invalid initiator random");
        result.status = 2;
        result.random = keccak256(abi.encodePacked(iRandom, result.aRandom));
        emit InitiatorReveal(randomID, result.random);
    }

    /* Internal Functions */
    function verifyProof(bytes32 randomID, address initiator, address acceptor, bytes32 iRandomHash, bytes memory iSig, bytes32 aRandom, bytes memory aSig) internal pure {
        bytes32 hash = keccak256(abi.encodePacked(randomID, initiator, acceptor, iRandomHash));
        require(hash.recover(iSig) == initiator, "invalid signature of initiator");
        hash = keccak256(abi.encodePacked(hash, aRandom));
        require(hash.recover(aSig) == acceptor, "invalid signature of acceptor");
    }
}
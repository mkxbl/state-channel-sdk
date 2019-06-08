// This is a very simple integration test because the time limits
// The code test a common process of dice game
// 1. Peer1 open channel
// 2. Peer2 Deposit Channel
// 3. Peer1 start a dice game off-chain, send game proof and random proof
// 4. Peer2 send lock transfer(lock game stake) to accept game
// 5. Peer1 send lock transfer(lock game stake) to peer2
// 6. Peer2 send game proof and random proof
// 7. Dispute when playing off-chain, peer2 go on-chain, force close channel 
// 8. Peer2 commit random proof to random contract
// 9. Peer2 commit game proof to game contract
// 10. Peer1 commit balance proof to channel contract
// 11. Peer1 commit pre-image to random contract
// 12. Peer1 settle channel
// 13. Peer1 unlock
// Need improvement in the future
const EthChannel = artifacts.require('EthChannel');
const DiceGame = artifacts.require('DiceGame');
const Random = artifacts.require('Random');
const testCase = require('./cases/game.json');
const signer = require('./helper/signer');
const miner = require('./helper/miner');
const RLP = require('rlp')

contract('Dice game', async accounts => {
    const peer1 = accounts[0];
    const peer2 = accounts[1];
    const privateKey1 = Buffer.from('326db97e36c23761c176683da11c53fbaf46db6e8ccc3f30836fd570f42e6668', 'hex');
    const privateKey2 = Buffer.from('3ae9e27a958d67ff8084dee43d8fbf5f611ee09bdd7768e58dde75301157f1b4', 'hex');
    let case1 = testCase[0];
    let nonce1 = 1;
    let nonce2 = 1;
    let channelInstance, gameInstance, randomInstance, channelID, randomID;
    let balanceHash1, balanceHash2, sig1, sig2, cSig, gpSig1, gpSig2, rpSig1, rpSig2; 

    before(async() => {
        randomInstance = await Random.new(9);
        gameInstance = await DiceGame.new(randomInstance.address);
        channelInstance = await EthChannel.new(gameInstance.address, 1, 9);
    })

    it('peer1 open channel, peer2 deposit', async() => {
        let res = await channelInstance.openChannel(peer1, peer2, 6, {from: peer1, value: case1[0]});
        channelID = res.receipt.logs[0].args[2];
        res = await channelInstance.depositChannel(channelID, peer2, {from: peer2, value:case1[1]});
        let channel = await channelInstance.id2channel.call(channelID);
        assert.equal(channel.status.toNumber(), 1);
    })

    it('play game off-chain', async() =>{
        // peer1 sign game proof
        let gameProof = {round: 1, channelID: channelID, initiator: peer1, acceptor: peer2, iStake: case1[4], aStake: case1[5], betMask: case1[6], modulo: case1[7]};
        let gameHash = web3.utils.soliditySha3(gameProof.round, gameProof.channelID, gameProof.initiator, gameProof.acceptor, gameProof.iStake, gameProof.aStake, gameProof.betMask, gameProof.modulo);
        gpSig1 = signer.sign(gameHash, privateKey1);
        // peer1 sign random proof
        let peersHash = await channelInstance.getPeersHash.call(peer1, peer2);
        randomID = web3.utils.soliditySha3(channelID, peersHash, 1);
        let randomProof = {randomID: randomID, initiator: peer1, acceptor: peer2, iRandomHash: web3.utils.soliditySha3({t:'bytes32', v:case1[12]})};
        let randomHash = web3.utils.soliditySha3(randomProof.randomID, randomProof.initiator, randomProof.acceptor, randomProof.iRandomHash);
        rpSig1 = signer.sign(randomHash, privateKey1);
        // peer2 send lock transfer
        balanceHash2 = web3.utils.soliditySha3(case1[3], case1[5], 1);
        let proofHash2 = web3.utils.soliditySha3(channelID, balanceHash2, nonce2);
        sig2 = signer.sign(proofHash2, privateKey2);
        // peer1 send lock transfer
        balanceHash1 = web3.utils.soliditySha3(case1[2], case1[4], 1);
        let proofHash1 = web3.utils.soliditySha3(channelID, balanceHash1, nonce1);
        sig1 = signer.sign(proofHash1, privateKey1);
        cSig = signer.sign(proofHash2, privateKey1);
        // peer2 sign game proof
        gpSig2 = signer.sign(gameHash, privateKey2);
        // peer2 sign random proof
        randomHash = web3.utils.soliditySha3({t: 'bytes32', v: randomHash}, {t: 'bytes32', v: case1[13]});
        rpSig2 = signer.sign(randomHash, privateKey2);
    })

    it('arbitration on-channel', async() => {
        // peer2 commit proof
        await channelInstance.fCloseChannel(peer1, balanceHash1, nonce1, sig1, {from: peer2});
        await randomInstance.acceptorCommitProof(randomID, peer1, peer2, web3.utils.soliditySha3({t:'bytes32', v:case1[12]}), rpSig1, case1[13], rpSig2);
        await gameInstance.commitProof(1, channelID, peer1, peer2, case1[4], case1[5], case1[6], case1[7], gpSig1, gpSig2);
        // peer1 commit proof
        await channelInstance.partnerCommitProof(peer1, peer2, balanceHash2, nonce2, sig2, cSig);
        await randomInstance.initiatorReveal(randomID, case1[12]);
        // peer1 settle channel
        await miner.mine(10);
        let data = [peer1, case1[2], case1[4], 1, peer2, case1[3], case1[5], 1];
        let res = await channelInstance.fSettleChannel(RLP.encode(data));
        let balance1 = res.receipt.logs[0].args[2];
        let balance2 = res.receipt.logs[0].args[4];
        assert.equal(balance1.toNumber(), case1[8]);
        assert.equal(balance2.toNumber(), case1[9]);
        // unlock
        res = await channelInstance.unlock(randomID, peer1, peer2);
        // console.log("unlock", res.receipt.logs[0].args);
        // console.log("peer1", res.receipt.logs[0].args[2].toNumber());
        // console.log("peer2", res.receipt.logs[0].args[4].toNumber());
        balance1 = res.receipt.logs[0].args[2];
        balance2 = res.receipt.logs[0].args[4];
        assert.equal(balance1.toNumber(), case1[10]);
        assert.equal(balance2.toNumber(), case1[11]);
    })
})
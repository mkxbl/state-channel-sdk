// This is a very simple integration test because the time limits
// The code test a common process of dice game
// 1. Open channel
// 2. Deposit Channel
// 3. Transfer value off-chain(direct transfer)
// 4. Peer1 start a dice game off-chain(lock transfer)
// 5. Dispute when playing off-chain 
// 6. Peer2 go on-chain, force close channel 
// 7. Peer2 commit random proof to random contract
// 8. Peer2 commit game proof to game contract
// 9. Peer1 commit balance proof to channel contract
// 10. Peer1 commit pre-image to random contract
// 11. Peer1 settle channel
// 12. Peer1 unlock
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

    let channelInstance, gameInstance, randomInstance;

    before(async() => {
        randomInstance = await Random.new(9);
        gameInstance = await DiceGame.new(randomInstance.address);
        channelInstance = await EthChannel.new(gameInstance, 1, 9);
    })

    it('case1', async() => {
        let case1 = testCase[0];
        // peer1 open channel
        let res = await myInstance.openChannel(peer1, peer2, 6, {from: peer1, value: case1[0]});
        channelID = res.receipt.logs[0].args[2];
        let nonce1 = 1;
        let nonce2 = 1;
        // peer1 transfer value to peer2 off-chain
        let balanceHash1 = web3.utils.soliditySha3(case1[2], 0, 0);
        let proofHash1 = web3.utils.soliditySha3(channelID, balanceHash1, nonce1++);
        let sig1 = signer.sign(proofHash1, privateKey1);
        // peer2 deposit
        res = await myInstance.depositChannel(channelID, peer2, {from: peer2, value:case1[1]});
        // peer2 tranfer value to peer1 off-chain
        let balanceHash2 = web3.utils.soliditySha3(case1[3], 0, 0);
        let proofHash2 = web3.utils.soliditySha3(channelID, balanceHash2, nonce2++);
        let sig2 = signer.sign(proofHash2, privateKey2);
        // peer1 start game
        let gameProof = {round: 1, channelID: channelID, initiator: peer1, acceptor: peer2, iStake: case1[4], aStake: case1[5], betMask: case1[6], modulo: case1[7]};
        let gameHash = web3.utils.soliditySha3(gameProof.round, gameProof.channelID, gameProof.initiator, gameProof.acceptor, gameProof.iStake, gameProof.aStake, gameProof.betMask, gameProof.modulo);
        let gpSig1 = signer.sign(gameHash, privateKey1);
        let peersHash = await channelInstance.getPeersHash.call(peer1, peer2);
        let randomID = web3.utils.soliditySha3(channelID, peersHash, 1);
        let randomProof = {randomID: randomID, initiator: peer1, acceptor: peer2, iRandomHash: web3.utils.soliditySha3(case1[12])};
        let randomHash = web3.utils.soliditySha3(randomProof.randomID, randomProof.initiator, randomProof.acceptor, randomProof.iRandomHash);
        let rpSig1 = signer.sign(randomHash, privateKey1);
    })
})
// This is a very simple integration test because the time limits
// The code test a common process of payment channel
// 1. Peer1 Open channel with peer2
// 2. Peer1 transfer value to peer2 off-chain
// 3. Peer2 deposit value in channel
// 4. Peer2 transfer value to peer1 off-chain
// 5. Arbitration on-channel, peer1 force close channel
// 6. Peer2 commit proof on-chain
// 7. waiting settle window over
// 8. settle channel on-chain
// Need improvement in the future

const EthChannel = artifacts.require('EthChannel');
const testCase = require('./cases/transfer.json');
const signer = require('./helper/signer');
const miner = require('./helper/miner');
const RLP = require('rlp')

contract('EthChannel', async accounts => {
    const peer1 = accounts[0];
    const peer2 = accounts[1];
    const privateKey1 = Buffer.from('326db97e36c23761c176683da11c53fbaf46db6e8ccc3f30836fd570f42e6668', 'hex');
    const privateKey2 = Buffer.from('3ae9e27a958d67ff8084dee43d8fbf5f611ee09bdd7768e58dde75301157f1b4', 'hex');
    let myInstance;
    
    before(async() => {
        myInstance = await EthChannel.new(accounts[3], 5, 10);
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
        let proofHash1 = web3.utils.soliditySha3(channelID, balanceHash1, nonce1);
        let sig1 = signer.sign(proofHash1, privateKey1);
        // peer2 deposit
        res = await myInstance.depositChannel(channelID, peer2, {from: peer2, value:case1[1]});
        // peer2 tranfer value to peer1 off-chain
        let balanceHash2 = web3.utils.soliditySha3(case1[3], 0, 0);
        let proofHash2 = web3.utils.soliditySha3(channelID, balanceHash2, nonce2);
        let sig2 = signer.sign(proofHash2, privateKey2);
        // peer1 force close channel
        res = await myInstance.fCloseChannel(peer2, balanceHash2, nonce2, sig2, {from: peer1});
        // peer2 commit proof
        let permitSig = signer.sign(proofHash1, privateKey2);
        res = await myInstance.partnerCommitProof(peer2, peer1, balanceHash1, nonce1, sig1, permitSig);
        // settle channel
        await miner.mine(10);
        let data = [peer1, case1[2], 0, 0, peer2, case1[3], 0, 0];
        res = await myInstance.fSettleChannel(RLP.encode(data));
        // assert settle result
        let balance1 = res.receipt.logs[0].args[2];
        let balance2 = res.receipt.logs[0].args[4];
        assert.equal(balance1.toNumber(), case1[4]);
        assert.equal(balance2.toNumber(), case1[5]);
    })
})
const ethUtil = require('ethereumjs-util');

function sign(messageHex, privateKey) {
    let messageBuffer = Buffer.from(messageHex.substring(2), 'hex');
    let signature = ethUtil.ecsign(messageBuffer, privateKey);
    signature = ethUtil.toRpcSig(signature.v, signature.r, signature.s).toString("hex");
    return web3.utils.hexToBytes(signature);
}

module.exports = {
    sign,
}
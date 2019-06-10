# stateChannel-diceGame contract (WIP) 

Contracts of state channel, support payment and dice game:

- payment: transfer value off-chain using secure, efficient and low-cost channel
- dice game: dApp based on state channel, including a off-chain random generation algorithm

## Payment

Simplified process: 

1. open channel on-chain
2. send balance proof off-chain
3. commit balance proof and settle channel

## Dice game 

Support mainstream gaming: flip-coin, dice, two-dice, etheroll

Off-chain random generation algorithm:

![Figure 1.](docs/random.png)

Random = hash(randomA, randomB)

## Two simple test

### Transfer value off-chain:
 1. Peer1 Open channel with peer2
 2. Peer1 transfer value to peer2 off-chain
 3. Peer2 deposit value in channel
 4. Peer2 transfer value to peer1 off-chain
 5. Arbitration on-channel, peer1 force close channel
 6. Peer2 commit proof on-chain
 7. waiting settle window over
 8. settle channel on-chain

<pre>
truffle test test/transfer.js
</pre>

 ### Play dice game off-chain
 1. Peer1 open channel
 2. Peer2 deposit Channel
 3. Peer1 start a dice game off-chain, send game proof and random proof
 4. Peer2 send lock transfer(lock game stake) to accept game
 5. Peer1 send lock transfer(lock game stake) to peer2
 6. Peer2 send game proof and random proof
 7. Dispute when playing off-chain, peer2 go on-chain, force close channel 
 8. Peer2 commit random proof to random contract
 9. Peer2 commit game proof to game contract
 10. Peer1 commit balance proof to channel contract
 11. Peer1 commit pre-image to random contract
 12. Peer1 settle channel
 13. Peer1 unlock

<pre>
truffle test test/game.js
</pre>
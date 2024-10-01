# Obelisk

# Introduction

Inspired by Heroglyphs where you can execute code based with a signature on your block’s graffiti. Obelisk uses the same logic for NFT’s. It creates a wrapper for existing collections, to then allow user to deposit into reward pools. To allow a collection, 100 ETH will be required. The ETH are deposited into a Liquidity Pool and are forever locked, all yields are sent to the Megapools Program.

# How to use

## NFT Pass

The NFT Pass is your Identity, without one, you won’t be able to set a signature. At a cost, you will be able to create you own and unique Identity. This Identity is a SBT (Soulbound Token) and cannot be transferred.


> [!NOTE]
> If you were holding any Herolgyphs NFTs at the snapshot time &lt;insert time&gt; then you can claim one free NFT pass.

## Signature

> [!WARNING]
> Max signature size is 25 bytes.

Like Heroglyphs, this signature is composed by two elements, the Identity and the Tickers.

### Identity:

The Identity is where the reward will be sent to, the syntax is represented by the symbol `@`. Example: `@atum` where `atum` is the name of my identity.

### Ticker

Compared to Heroglyphs, Tickers cannot be created by the public, only the contract owner can add them. It also doesn’t have any taxes or hijacking. The ticker is the code execution destination, the syntax is represented by the symbol `#` . Example `#megapool01#megapool02` where megapool01 & 02 are tickers (no space required).

#### Cost

**90 HCT** is required to set / change your signature unless it is an Hashmask NFT (see below)

#### Hashmask

> [!NOTE]
> Hashmask **doesn’t require Identity** and the ticker syntax is O (not o — case-sensitive) instead of `#` \n 
> Example: Omegapool01 Opepe \n
>**Space Required**

Hashmask has a direct implementation that uses hashmask’s syntax. Instead of renaming a wrapped version of the hashmask nft, you will be renaming your hashmask directly and update it on Obelisk.

First, you will need to link your Hashmask to Obelisk which will cost 0.1 ETH. If the Hashmask holder is modified, the new holder will need to re-link and pay the 0.1 ETH, unless the previous owner transfer the link’s ownership for free.

> [!IMPORTANT]
> Since Hashmask is not directly in our system, you will need to claim your rewards before transferring or changing the name. If the owner or the name is not the same at the time of the claiming — **YOU WILL LOSE YOUR REWARDS.**

# Megapools

Megapools are unique pools that will be receiving the yield from all the ETH collected. All megapools are limited to 1000 deposits and rewards are based on the Gauge System. By using the HCT Token, the user can delegate its power to vote on one of his megapools. The votes will define how much shares the pool will be receiving from the yield during the next epoch.

# HTC Token

Hero Token Name Change is the token used to rename your NFT. Inspired from Hashmask, if a user wishes to change the NFT name (change its signature), they will be required to pay a fee in HCT. There are only two ways to have HCT:

1.  Buying from the market
2.  Farming from the an Obelisk NFT Version.

Meaning, you will need to buy HCT to set your initial signature.

> [!NOTE]
> Premium Obelisk NFT Version (which are only created by the team) has one free renaming. If an NFT is being wrapped, for the first time, into a Premium Obelisk NFT, the holder will have access to set the first signature for free.

## Reward Rate

Each Obelsik NFT has a multiplier based on how old the collection is. The multiplier is defined by the follow formula

$$\\text{CollectionMultiplier} = \\min(\\frac{\\text{currentTimestamp} - \\text{collectionDeploymentTimestamp}}{31,557,600}, 3)$$

The HCT reward per second is defined by

$$\\text{HCTPerSecond} = \\frac{\\sqrt{\\text{userTotalNFTs} \\times \\text{averageMultiplier}}}{1 \\text{ day}}$$

# Obelisk NFT Version

The Obelisk NFT Version is a modified wrapped version of any ERC721 collection that has been approved & activate by the community. Once the process is completed, it automatically creates a wrapped version in which it will contains all the logic required to use Obelisk.

### Premium Obelisk NFT

Premium Obelisk NFT can only be created by the contract owner of the Registry. Once a collection is approved or created, the premium flag cannot be changed. A premium collection sets the multiplier at 3x no matter the age of the collection & gives on free name renaming for the first time an NFT is being wrapped.

> [!WARNING]
> Free name is based on the NFT ID and can only be used once.

# Heroglyphs VS Obelisk

|     |     |     |
| --- | --- | --- |
| Features | Obelisk | Heroglyphs |
| Identity | ✅   | ✅   |
| — Cost | 0.1 ETH | 0.1 ETH |
| — Required | ✅   | ✅   |
| — Linked to an Entity | ❌   | ✅ (Validator ID) |
| — Soulbound | ✅   | ✅   |
| Ticker | ✅   | ✅   |
| — Permisionless | ❌   | ✅   |
| — Harberger Tax | ❌   | ✅   |
| — Hijackable | ❌   | ✅   |
| Signature | ✅   | ✅   |
| — Max Bytes | 25 bytes | 32 bytes |
| — Cost on Signature Modification | 90 HCT | FREE |
| — Cross-chain Syntax | ❌   | ✅   |
| MegaPools | ✅   | ❌   |
| Chain | Mainnet | Arbitrum |
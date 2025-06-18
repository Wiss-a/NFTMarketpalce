// async function main() {
//     // Fetch the contract factory for your NFT collection
//     const NFTCollection = await ethers.getContractFactory("NFTCollection");
  
//     // Deploy the contract
//     const nft = await NFTCollection.deploy();
//     await nft.deployed();
  
//     // Log the contract address after deployment
//     console.log(`✅ NFTCollection deployed to: ${nft.address}`);
//     async function mintNFT() {
//         const [minter] = await ethers.getSigners(); // Use the deployer's wallet to mint
//         console.log("Minting NFT from account:", minter.address);
        
//         // Assuming your contract has a mint function
//         const nftCollection = await ethers.getContractAt("NFTCollection", contract.address);
//         const tokenURI = "ipfs://your-token-uri";  // Replace with actual IPFS URL or metadata
        
//         const tx = await nftCollection.mint(minter.address, tokenURI);
//         console.log("Mint transaction sent:", tx.hash);
        
//         // Wait for transaction to be mined
//         const receipt = await tx.wait();
//         console.log("NFT minted successfully:", receipt);
//       }
      
//       mintNFT().catch(console.error);
      
//   }

  
//   // Run the deployment script
//   main()
//     .then(() => process.exit(0))
//     .catch((error) => {
//       console.error("❌ Deployment failed:", error);
//       process.exit(1);
// });
async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deploying contracts with the account:", deployer.address);
  
    const NFTCollection = await ethers.getContractFactory("NFTCollection");
    const nftCollection = await NFTCollection.deploy();
    console.log("NFTCollection deployed to:", nftCollection.address);
  }
  
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });
  
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("NFTCollection", function () {
  let NFTCollection;
  let nftCollection;
  let owner;
  let addr1;
  let addr2;
  
  beforeEach(async function () {
    // Get the ContractFactory and Signers here
    NFTCollection = await ethers.getContractFactory("NFTCollection");
    [owner, addr1, addr2] = await ethers.getSigners();
    
    // Deploy a new NFTCollection contract before each test
    nftCollection = await NFTCollection.deploy();
    await nftCollection.deployed();
  });
  
  describe("Deployment", function () {
    it("Should set the right name and symbol", async function () {
      expect(await nftCollection.name()).to.equal("SchoolProject");
      expect(await nftCollection.symbol()).to.equal("SCHL");
    });
    
    it("Should set the right owner", async function () {
      expect(await nftCollection.owner()).to.equal(owner.address);
    });
  });
  
  describe("Minting", function () {
    it("Should mint a new token and assign it to the specified address", async function () {
      const tokenURI = "ipfs://bafybeibbw5uwppsrijcfpj7w6b7q6g66iqzuy5tqwnrv5udcl2ku2vztky";
      
      await nftCollection.mint(addr1.address, tokenURI);
      
      expect(await nftCollection.ownerOf(1)).to.equal(addr1.address);
      expect(await nftCollection.tokenURI(1)).to.equal(tokenURI);
      expect(await nftCollection.totalSupply()).to.equal(1);
    });
    
    it("Should emit Transfer event during minting", async function () {
      const tokenURI = "ipfs://bafybeibbw5uwppsrijcfpj7w6b7q6g66iqzuy5tqwnrv5udcl2ku2vztky";
      
      await expect(nftCollection.mint(addr1.address, tokenURI))
        .to.emit(nftCollection, "Transfer")
        .withArgs(ethers.constants.AddressZero, addr1.address, 1);
    });
  });
  
  describe("Token URIs", function () {
    it("Should set and retrieve token URIs correctly", async function () {
      const tokenURI1 = "ipfs://bafybeibbw5uwppsrijcfpj7w6b7q6g66iqzuy5tqwnrv5udcl2ku2vztky";
      const tokenURI2 = "ipfs://bafybeibbw5uwppsrijcfpj7w6b7q6g66iqzuy5tqwnrv5udcl2ku2vztky";
      
      await nftCollection.mint(addr1.address, tokenURI1);
      await nftCollection.mint(addr2.address, tokenURI2);
      
      expect(await nftCollection.tokenURI(1)).to.equal(tokenURI1);
      expect(await nftCollection.tokenURI(2)).to.equal(tokenURI2);
    });
  });
  
  describe("Collection URI", function () {
    it("Should set and retrieve collection URI correctly", async function () {
      const collectionURI = "ipfs://QmCollectionMetadata";
      
      await nftCollection.setCollectionURI(collectionURI);
      
      expect(await nftCollection.collectionURI()).to.equal(collectionURI);
    });
    
    it("Should allow only owner to set collection URI", async function () {
      const collectionURI = "ipfs://QmCollectionMetadata";
      
      // Should revert with a message containing 'owner'
      await expect(
        nftCollection.connect(addr1).setCollectionURI(collectionURI)
      ).to.be.revertedWith("Ownable: caller is not the owner");
      
      // Owner should be able to set the URI
      await nftCollection.setCollectionURI(collectionURI);
      expect(await nftCollection.collectionURI()).to.equal(collectionURI);
    });
  });
});
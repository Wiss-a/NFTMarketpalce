// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";

contract NFTCollection is ERC721, Ownable, ReentrancyGuard, IERC2981 {
    uint256 private _tokenIds;
    address private _defRecipient;
    uint16 private _defFraction;
    uint16 constant MAX_ROYALTY = 1000;
    
    mapping(uint256 => uint256) private _royalties;
    mapping(uint256 => string) private _tokenURIs;
    
    enum SaleType { Fixed, Auction }
    
    struct Listing {
        address seller;
        uint256 tokenId;
        uint256 price;
        SaleType saleType;
        uint256 auctionEndTime;
        uint256 highestBid;
        address highestBidder;
        bool active;
        uint256 listingTime;
    }

    mapping(uint256 => Listing) public listings;
    uint256[] public activeListings;
    mapping(uint256 => uint256) private listingIndex;
    mapping(uint256 => mapping(address => uint256)) public auctionBids;
    mapping(uint256 => address[]) public bidders;
    mapping(uint256 => mapping(address => uint256)) private bidderIndex;

    // Legacy
    struct Ask { address seller; uint256 tokenId; uint256 price; bool active; }
    struct Bid { address buyer; uint256 price; bool active; }
    Ask[] public asks;
    Bid[] public bids;

    event NFTListed(uint256 indexed tokenId, address indexed seller, uint256 price, SaleType saleType);
    event NFTSold(uint256 indexed tokenId, address indexed seller, address indexed buyer, uint256 price);
    event BidPlaced(uint256 indexed tokenId, address indexed bidder, uint256 amount);
    event BidWithdrawn(uint256 indexed tokenId, address indexed bidder, uint256 amount);
    event AuctionEnded(uint256 indexed tokenId, address indexed winner, uint256 amount);
    event ListingCancelled(uint256 indexed tokenId);
    event RoyaltyPaid(uint256 indexed tokenId, address indexed recipient, uint256 amount);

    modifier validToken(uint256 tokenId) {
        _requireOwned(tokenId);
        _;
    }

    constructor() ERC721("NFTMarketplace", "MNFT") Ownable(msg.sender) {}

    function mint(string memory uri) external returns (uint256) {
        uint256 id = ++_tokenIds;
        _mint(msg.sender, id);
        _tokenURIs[id] = uri;
        return id;
    }

    function tokenURI(uint256 tokenId) public view virtual override validToken(tokenId) returns (string memory) {
        return _tokenURIs[tokenId];
    }

    function totalSupply() external view returns (uint256) { 
        return _tokenIds; 
    }

    // Compact royalty functions
    function setDefaultRoyalty(address recipient, uint16 fraction) external onlyOwner {
        require(fraction <= MAX_ROYALTY && recipient != address(0));
        _defRecipient = recipient;
        _defFraction = fraction;
    }

    function setTokenRoyalty(uint256 tokenId, address recipient, uint16 fraction) external {
        require(_ownerOf(tokenId) == msg.sender || owner() == msg.sender);
        require(fraction <= MAX_ROYALTY && recipient != address(0));
        _royalties[tokenId] = (uint256(uint160(recipient)) << 16) | fraction;
    }

    function royaltyInfo(uint256 tokenId, uint256 salePrice) external view override returns (address, uint256) {
        uint256 r = _royalties[tokenId];
        address recipient = r != 0 ? address(uint160(r >> 16)) : _defRecipient;
        uint16 fraction = r != 0 ? uint16(r) : _defFraction;
        return (recipient, (salePrice * fraction) / 10000);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, IERC165) returns (bool) {
        return interfaceId == type(IERC2981).interfaceId || super.supportsInterface(interfaceId);
    }

    function _payRoyalty(uint256 tokenId, uint256 price) private returns (uint256) {
        (address recipient, uint256 amount) = this.royaltyInfo(tokenId, price);
        if (amount > 0 && recipient != address(0)) {
            payable(recipient).transfer(amount);
            emit RoyaltyPaid(tokenId, recipient, amount);
        }
        return amount;
    }

    function listNFTFixedPrice(uint256 tokenId, uint256 price) external {
        require(ownerOf(tokenId) == msg.sender && price > 0 && !listings[tokenId].active);
        
        listings[tokenId] = Listing({
            seller: msg.sender,
            tokenId: tokenId,
            price: price,
            saleType: SaleType.Fixed,
            auctionEndTime: 0,
            highestBid: 0,
            highestBidder: address(0),
            active: true,
            listingTime: block.timestamp
        });
        
        activeListings.push(tokenId);
        listingIndex[tokenId] = activeListings.length - 1;
        
        emit NFTListed(tokenId, msg.sender, price, SaleType.Fixed);
    }

    function listNFTAuction(uint256 tokenId, uint256 startingPrice, uint256 durationInSeconds) external {
        require(ownerOf(tokenId) == msg.sender && startingPrice > 0 && 
                durationInSeconds > 0 && durationInSeconds <= 86400 && !listings[tokenId].active);
        
        listings[tokenId] = Listing({
            seller: msg.sender,
            tokenId: tokenId,
            price: startingPrice,
            saleType: SaleType.Auction,
            auctionEndTime: block.timestamp + durationInSeconds,
            highestBid: 0,
            highestBidder: address(0),
            active: true,
            listingTime: block.timestamp
        });
        
        activeListings.push(tokenId);
        listingIndex[tokenId] = activeListings.length - 1;
        
        emit NFTListed(tokenId, msg.sender, startingPrice, SaleType.Auction);
    }

    function buyNFT(uint256 tokenId) external payable nonReentrant {
        Listing storage listing = listings[tokenId];
        require(listing.active && listing.saleType == SaleType.Fixed && 
                msg.value >= listing.price && msg.sender != listing.seller);
        
        address seller = listing.seller;
        uint256 price = listing.price;
        
        _removeListing(tokenId);
        _transfer(seller, msg.sender, tokenId);
        
        uint256 royaltyAmount = _payRoyalty(tokenId, price);
        payable(seller).transfer(price - royaltyAmount);
        
        if (msg.value > price) {
            payable(msg.sender).transfer(msg.value - price);
        }
        
        emit NFTSold(tokenId, seller, msg.sender, price);
    }

    function placeBid(uint256 tokenId) external payable nonReentrant {
        Listing storage listing = listings[tokenId];
        require(listing.active && listing.saleType == SaleType.Auction && 
                block.timestamp < listing.auctionEndTime && msg.sender != listing.seller);
        
        uint256 minBid = listing.highestBid > 0 ? listing.highestBid + 0.0001 ether : listing.price;
        require(msg.value >= minBid);
        
        uint256 existingBid = auctionBids[tokenId][msg.sender];
        if (existingBid > 0) {
            payable(msg.sender).transfer(existingBid);
        } else {
            bidders[tokenId].push(msg.sender);
            bidderIndex[tokenId][msg.sender] = bidders[tokenId].length - 1;
        }
        
        auctionBids[tokenId][msg.sender] = msg.value;
        
        if (msg.value > listing.highestBid) {
            listing.highestBid = msg.value;
            listing.highestBidder = msg.sender;
        }
        
        emit BidPlaced(tokenId, msg.sender, msg.value);
    }

    function withdrawBid(uint256 tokenId) external nonReentrant {
        Listing storage listing = listings[tokenId];
        require(listing.active && listing.saleType == SaleType.Auction && 
                msg.sender != listing.highestBidder);
        
        uint256 bidAmount = auctionBids[tokenId][msg.sender];
        require(bidAmount > 0);
        
        auctionBids[tokenId][msg.sender] = 0;
        _removeBidder(tokenId, msg.sender);
        
        payable(msg.sender).transfer(bidAmount);
        
        emit BidWithdrawn(tokenId, msg.sender, bidAmount);
    }

    function _removeBidder(uint256 tokenId, address bidder) private {
        uint256 index = bidderIndex[tokenId][bidder];
        uint256 lastIndex = bidders[tokenId].length - 1;
        
        if (index != lastIndex) {
            address lastBidder = bidders[tokenId][lastIndex];
            bidders[tokenId][index] = lastBidder;
            bidderIndex[tokenId][lastBidder] = index;
        }
        
        bidders[tokenId].pop();
        delete bidderIndex[tokenId][bidder];
    }

    function endAuction(uint256 tokenId) external nonReentrant {
        Listing storage listing = listings[tokenId];
        require(listing.active && listing.saleType == SaleType.Auction && 
                block.timestamp >= listing.auctionEndTime);
        
        address seller = listing.seller;
        
        if (listing.highestBidder != address(0)) {
            _transfer(seller, listing.highestBidder, tokenId);
            
            uint256 royaltyAmount = _payRoyalty(tokenId, listing.highestBid);
            payable(seller).transfer(listing.highestBid - royaltyAmount);
            
            _refundOtherBidders(tokenId, listing.highestBidder);
            
            emit AuctionEnded(tokenId, listing.highestBidder, listing.highestBid);
            emit NFTSold(tokenId, seller, listing.highestBidder, listing.highestBid);
        } else {
            emit AuctionEnded(tokenId, address(0), 0);
        }
        
        _cleanupAuctionData(tokenId);
        _removeListing(tokenId);
    }

    function _refundOtherBidders(uint256 tokenId, address winner) private {
        address[] storage tokenBidders = bidders[tokenId];
        for (uint256 i = 0; i < tokenBidders.length; i++) {
            address bidder = tokenBidders[i];
            if (bidder != winner) {
                uint256 bidAmount = auctionBids[tokenId][bidder];
                if (bidAmount > 0) {
                    payable(bidder).transfer(bidAmount);
                }
            }
        }
    }

    function _cleanupAuctionData(uint256 tokenId) private {
        address[] storage tokenBidders = bidders[tokenId];
        for (uint256 i = 0; i < tokenBidders.length; i++) {
            address bidder = tokenBidders[i];
            delete auctionBids[tokenId][bidder];
            delete bidderIndex[tokenId][bidder];
        }
        delete bidders[tokenId];
    }

    function cancelListing(uint256 tokenId) external {
        Listing storage listing = listings[tokenId];
        require(listing.active && listing.seller == msg.sender);
        
        if (listing.saleType == SaleType.Auction) {
            _refundAllBidders(tokenId);
            _cleanupAuctionData(tokenId);
        }
        
        _removeListing(tokenId);
        emit ListingCancelled(tokenId);
    }

    function _refundAllBidders(uint256 tokenId) private {
        address[] storage tokenBidders = bidders[tokenId];
        for (uint256 i = 0; i < tokenBidders.length; i++) {
            address bidder = tokenBidders[i];
            uint256 bidAmount = auctionBids[tokenId][bidder];
            if (bidAmount > 0) {
                payable(bidder).transfer(bidAmount);
            }
        }
    }

    function _removeListing(uint256 tokenId) private {
        uint256 index = listingIndex[tokenId];
        uint256 lastIndex = activeListings.length - 1;
        
        if (index != lastIndex) {
            uint256 lastToken = activeListings[lastIndex];
            activeListings[index] = lastToken;
            listingIndex[lastToken] = index;
        }
        
        activeListings.pop();
        delete listingIndex[tokenId];
        listings[tokenId].active = false;
    }

    // View functions
    function getListing(uint256 tokenId) external view returns (Listing memory) {
        return listings[tokenId];
    }

    function getBidHistory(uint256 tokenId) external view returns (address[] memory, uint256[] memory) {
        address[] memory tokenBidders = bidders[tokenId];
        uint256[] memory amounts = new uint256[](tokenBidders.length);
        
        for (uint256 i = 0; i < tokenBidders.length; i++) {
            amounts[i] = auctionBids[tokenId][tokenBidders[i]];
        }
        
        return (tokenBidders, amounts);
    }

    function getUserBid(uint256 tokenId, address user) external view returns (uint256) {
        return auctionBids[tokenId][user];
    }

    function getRoyaltyInfo(uint256 tokenId, uint256 salePrice) external view returns (address, uint256) {
        return this.royaltyInfo(tokenId, salePrice);
    }

    function getActiveListings() external view returns (uint256[] memory) { 
        return activeListings; 
    }
    
    function isListed(uint256 tokenId) external view returns (bool) { 
        return listings[tokenId].active; 
    }

    // Minimal legacy functions
    function createAsk(uint256 tokenId, uint256 price) external {
        require(ownerOf(tokenId) == msg.sender);
        transferFrom(msg.sender, address(this), tokenId);
        asks.push(Ask(msg.sender, tokenId, price, true));
        _matchOrders();
    }

    function createBid() external payable {
        require(msg.value > 0);
        bids.push(Bid(msg.sender, msg.value, true));
        _matchOrders();
    }

    function _matchOrders() private {
        for (uint256 i = 0; i < asks.length; i++) {
            if (!asks[i].active) continue;
            for (uint256 j = 0; j < bids.length; j++) {
                if (!bids[j].active || bids[j].price < asks[i].price) continue;
                
                uint256 tokenId = asks[i].tokenId;
                address seller = asks[i].seller;
                address buyer = bids[j].buyer;

                _transfer(address(this), buyer, tokenId);
                uint256 royalty = _payRoyalty(tokenId, asks[i].price);
                payable(seller).transfer(asks[i].price - royalty);

                if (bids[j].price > asks[i].price) {
                    payable(buyer).transfer(bids[j].price - asks[i].price);
                }

                asks[i].active = false;
                bids[j].active = false;
                break;
            }
        }
    }
}
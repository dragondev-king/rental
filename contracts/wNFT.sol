//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/IERC721URI.sol";

contract wNFT is Ownable, IERC721Receiver, ERC721Enumerable, ReentrancyGuard {
  enum WrapStatus {
    FREE,
    REQUEST_PENDING,
    RENTED,
    RENTAL_OVER
  }

  /// @dev keep original NFT data
  struct Wrap {
    IERC721URI nftAddr;
    address renter;
    address owner;
    ///@dev min rental period in days, set by token owner
    uint256 minRentalPeriod;
    ///@dev max rental period in days, set by token owner
    uint256 maxRentalPeriod;
    ///@dev rental period in days, actually agreed between renter and owner
    uint256 rentalPeriod;
    ///@dev rent start timestamp
    uint256 rentStarted;
    uint256 dailyRate;
    uint256 tokenId;
  }

  /// @dev token id tracker
  uint256 internal tokenIdTracker;

  /// @dev token id => wrap
  mapping(uint256 => Wrap) public wraps;

  /// @dev owner address => amount
  mapping(address => uint256) public ownerBalance;

  ///@dev servie fee percentage
  uint256 public serviceFeeRatio;

  /// events
  event Registered(address owner, address nftAddr, uint256 tokenId);

  event Unregistered(address owner, address nftAddr, uint256 tokenId);

  event RentRequested(address renter, address owner, uint256 tokenId, Wrap data);

  event RentStarted(address renter, address owner, uint256 tokenId, Wrap data);

  event RentEnded(address renter, address owner, uint256 tokenId, Wrap data);

  event RentDenied(address renter, address owner, uint256 tokenId, Wrap data); 

  event ServiceFeeRatioSet(uint256 percentage);

  event ownerBalanceWithdrawn(address owner, uint256 amount);

  event ServiceFeeBalanceWithdrawn(address recipient, uint256 amount);


  /// @dev constructor
  constructor(uint256 _serviceFeeRatio) ERC721("wNFT", "wNFT") Ownable() ReentrancyGuard() {
    require(_serviceFeeRatio < 100, "wNFT: invalid service fee");
    serviceFeeRatio = _serviceFeeRatio;
  }

  modifier onlyValidToken(uint256 tokenId) {
    require(_exists(tokenId), "wNFT: invalid wrap token id");
    _;
  }

  receive() external payable { }

  /**
    * @dev Returns wrap token status
    * @param tokenId wrap token id
    */
  function tokenStatus(uint256 tokenId) public view onlyValidToken(tokenId) returns(WrapStatus) {
    Wrap storage wrap = wraps[tokenId];
    if(wrap.renter == address(0)) {
      return WrapStatus.FREE;
    } else if(wrap.rentStarted == 0) {
      return WrapStatus.REQUEST_PENDING;
    } else if(
      wrap.rentStarted + wrap.rentalPeriod * 1 days < block.timestamp
    ) {
      return WrapStatus.RENTAL_OVER;
    } else {
      return WrapStatus.RENTED;
    }
  }
  
  /**
    * @dev Registers token and mint wNFT to the token owner
    * @param nftAddr token address
    * @param tokenId token id
    * @param minRentalPeriod min rental period in days
    * @param maxRentalPeriod max rental period in days
    * @param dailyRate daily rate
    */
  function register(
    address nftAddr,
    uint256 tokenId,
    uint256 minRentalPeriod,
    uint256 maxRentalPeriod,
    uint256 dailyRate
  ) external payable nonReentrant {
    require(nftAddr != address(this), "wNFT: cannot register wNFT");

    address owner = IERC721URI(nftAddr).ownerOf(tokenId);
    
    require(msg.sender == owner, "wNFT: caller is not the owner of the NFT");
    require(minRentalPeriod > 0, "wNFT: zero min reltal period");
    require(minRentalPeriod < maxRentalPeriod, "wNFT: invalid max reltal period");
    require(dailyRate > 0, "wNFT: zero daily rate");

    uint256 newTokenId = tokenIdTracker;
    Wrap storage wrap = wraps[newTokenId];

    tokenIdTracker += 1;

    //storage original nft data
    wrap.nftAddr = IERC721URI(nftAddr);
    wrap.owner = owner;
    wrap.tokenId = tokenId;
    wrap.minRentalPeriod = minRentalPeriod;
    wrap.maxRentalPeriod = maxRentalPeriod;
    wrap.dailyRate = dailyRate;

    //escrow the nft
    wrap.nftAddr.safeTransferFrom(owner,address(this), tokenId);
    //mint wNFT
    _safeMint(address(this), newTokenId);

    emit Registered(msg.sender, nftAddr, tokenId);
  }

  
  /**
    * @dev Unregisters wrap and send token back to the owner
    * @param tokenId wrap token id
    */
  function unregister(uint256 tokenId) external onlyValidToken(tokenId) nonReentrant {
    Wrap storage wrap = wraps[tokenId];
    address nftAddr = address(wrap.nftAddr);

    require(tokenStatus(tokenId) == WrapStatus.FREE, "wNFT: cannot unregister non free wrap");
    require(wrap.owner == msg.sender, "wNFT: only token owner can unregister");

    _burn(tokenId);
    tokenId = wrap.tokenId;

    wrap.nftAddr.safeTransferFrom(address(this), msg.sender, tokenId);
    delete wraps[tokenId];

    emit Unregistered(msg.sender, nftAddr, tokenId);
  }
}

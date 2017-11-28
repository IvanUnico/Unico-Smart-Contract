pragma solidity ^0.4.17;


contract UnicoToken {

    uint private constant PERCENTAGE_MULTIPLIER = 10; 

   //Collectible structure, has data of the collectible
    struct Collectible {
        uint256 uniqueIdentifier; 
        string name; 
        address author;
        uint256 buyPrice;
    }

    struct HereMeNowExtension {
        uint256 nowStart; //Timestamp of when the NOW starts
        uint256 nowMinutesDuration; //Duration in minutes of NOW
                                    //At nowStart + nowMinutesDuration will not be possible to claim the NOW anymore
        Here here;  //HERE of the collectible
        bool hereMeNowOnlyAdmins; //specify if the Here/Me/Now can be claimed only admins
                                  //To support different method of verification by admins of the correct here/me/now
                                  //avoiding user hacks gps/time to claim here/me/now
    }

    struct Royalty {
        address user;
        uint256 amount;
    }

    //License structure, has data of user
    struct License {
        uint256 collectibleUniqueIdentifier;
        uint256 number; 
        address owner;  
        uint256 buyPrice;  
        SellOptions sellOptions;
        HereMeNow hereMeNow;
    }

    struct Here {
        uint256 latitude;
        uint256 longitude;
        uint256 radiusMeters;
    }

    struct HereMeNow {
        Here here;
        address me;
        uint256 timestamp;
    }

    struct SellOptions {
        bool selling;
        uint256 price;
        address buyer;
    }

    mapping(address=>bool) private admins;
    uint256 private adminsCount;

    mapping(uint256=>HereMeNowExtension[]) private hereMeNowOfCollectible;
    mapping(uint256=>uint) public totalSupplyOfCollectible;
    mapping(uint256=>uint) public availableSupplyOfCollectible;
    mapping(uint256=>License[]) private licensesOfCollectible;

    Collectible[] public collectibles;
    mapping(uint256=>Collectible) public collectibleList;
    mapping(uint256=>Royalty[]) public royaltiesOfCollectible;
    mapping(address=>Collectible[]) public collectiblesOfUser;
    mapping(uint256=>address[]) public usersOfCollectible;

    event OutOfLicenses();
    event InsufficientFunds();

    modifier onlyByAdmins() {
        require(isAdmin(msg.sender));
        _;
    }

    modifier onlyByOwner(uint256 uniqueIdentifier, uint256 licenseNumber) {
        require(msg.sender == licensesOfCollectible[uniqueIdentifier][licenseNumber].owner);
        _;
    }

    function UnicoToken() public {
        admins[msg.sender] = true;
        adminsCount += 1;
    }

    function createCollectible(
        uint256 uniqueIdentifier,
        string name,
        uint initialSupply,
        address author,
        uint256 buyPrice,
        address[] royaltyAddresses,
        uint256[] royaltyAmount,
        uint256 latitude,
        uint256 longitude,
        uint256 radiusMeters,
        uint256 nowStart,
        uint256 nowMinutesDuration
        ) public onlyByAdmins()
    {
        require(initialSupply > 0);
        require(author != address(0x0));
        require(royaltiesAreCorrect(royaltyAddresses, royaltyAmount));
        require(!collectibleExists(uniqueIdentifier));

        Collectible memory c;
        c.uniqueIdentifier = uniqueIdentifier;
        c.name = name;
        c.author = author;
        c.buyPrice = buyPrice;
        if (royaltyAddresses.length > 0) {
            manageRoyalties(c, royaltyAddresses, royaltyAmount);
        }
        manageHereMeNow(c.uniqueIdentifier, nowStart, nowMinutesDuration, latitude, longitude, radiusMeters);

        collectibles.push(c);
        collectibleList[c.uniqueIdentifier] = c;
        totalSupplyOfCollectible[c.uniqueIdentifier] = initialSupply;
        availableSupplyOfCollectible[c.uniqueIdentifier] = initialSupply;
    }

    function buyCollectible(uint256 collectibleUniqueIdentifier) public payable {
        //Collectible must exists!
        require(collectibleList[collectibleUniqueIdentifier].uniqueIdentifier == collectibleUniqueIdentifier);

        Collectible memory c = collectibleList[collectibleUniqueIdentifier];
        if (availableSupplyOfCollectible[collectibleUniqueIdentifier] == 0) {
            OutOfLicenses();
            revert();
        }
        if (msg.value < c.buyPrice) {
            InsufficientFunds();
            revert();
        }

        License[] storage licenses = licensesOfCollectible[c.uniqueIdentifier];

        License memory lic;
        lic.collectibleUniqueIdentifier = c.uniqueIdentifier;
        lic.number = licenses.length + 1;
        lic.owner = msg.sender;
        lic.buyPrice = c.buyPrice;
        licenses.push(lic);

        availableSupplyOfCollectible[collectibleUniqueIdentifier] -= 1;
        collectiblesOfUser[msg.sender].push(c);
        usersOfCollectible[collectibleUniqueIdentifier].push(msg.sender);

        uint256 totalRoyalties = 0;
        Royalty[] storage royalties = royaltiesOfCollectible[c.uniqueIdentifier];
        for (uint256 index = 0; index < royalties.length; index++) {
            uint256 royalty = royalties[index].amount * c.buyPrice / (100 * PERCENTAGE_MULTIPLIER);
            totalRoyalties += royalty;
            royalties[index].user.transfer(royalty);
        }
        c.author.transfer(c.buyPrice - totalRoyalties);
        if (msg.value > c.buyPrice) {
            msg.sender.transfer(msg.value - c.buyPrice);
        }
    }

    function sellLicense(uint256 uniqueIdentifierOfCollectible, uint256 licenseNumber,
    bool selling, uint256 price, address buyer) public
    onlyByOwner(uniqueIdentifierOfCollectible, licenseNumber) {
        License storage lic = licensesOfCollectible[uniqueIdentifierOfCollectible][licenseNumber];
        SellOptions storage opt = lic.sellOptions;
        opt.selling = selling;
        opt.price = price;
        opt.buyer = buyer;
    }

    function presentLicense(uint256 uniqueIdentifierOfCollectible, uint256 licenseNumber, address receiver) public
    onlyByOwner(uniqueIdentifierOfCollectible, licenseNumber) {
        require(receiver != address(0x0));
        License storage lic = licensesOfCollectible[uniqueIdentifierOfCollectible][licenseNumber];
        SellOptions storage opt = lic.sellOptions;
        opt.selling = false;
        opt.price = 0;
        opt.buyer = address(0x0);
        lic.owner = receiver;
    }

    function buyLicense(uint256 uniqueIdentifierOfCollectible, uint256 licenseNumber) public payable {
        License storage lic = licensesOfCollectible[uniqueIdentifierOfCollectible][licenseNumber];
        SellOptions storage opt = lic.sellOptions;

        require(opt.selling);
        require(msg.value >= opt.price);
        require(opt.buyer == address(0x0) || opt.buyer == msg.sender);

        lic.owner = msg.sender;
        opt.selling = false;
        opt.price = 0;
        opt.buyer = address(0x0);
        if (msg.value > opt.price) {
            msg.sender.transfer(msg.value - opt.price);
        }
        lic.owner.transfer(msg.value);
    }

    function addAdmin(address newAdmin) public onlyByAdmins() {
        if (!isAdmin(newAdmin)) {
            admins[newAdmin] = true;
            adminsCount += 1;
        }
    }

    function removeAdmin(address adminToRemove) public onlyByAdmins() {
        if (adminsCount > 1 && isAdmin(adminToRemove)) {
            admins[adminToRemove] = false;
            adminsCount -= 1;
        }
    }

    function getAdminsCount() public view onlyByAdmins()
    returns (uint256 adminsList) {
        return adminsCount;
    }

    function getCollectibleName(uint256 uniqueIdentifier) public view
    returns (string title) {
        return collectibleList[uniqueIdentifier].name;
    }

    function collectibleExists(uint256 uniqueIdentifier) private view
    returns (bool exists) {
        return collectibleList[uniqueIdentifier].uniqueIdentifier != 0;
    }

    function manageRoyalties(Collectible c, address[] royaltyAddresses, uint256[] royaltyAmount) private {
        Royalty[] storage royalties = royaltiesOfCollectible[c.uniqueIdentifier];
        for (uint index = 0; index < royaltyAddresses.length; index++) {
            royalties.push(Royalty(royaltyAddresses[index], royaltyAmount[index]));
        }
    }

    function manageHereMeNow(
        uint256 uniqueIdentifier,
        uint256 nowStart,
        uint256 nowMinutesDuration,
        uint256 latitude,
        uint256 longitude,
        uint256 radiusMeters) private {
        if (nowStart > 0 || latitude != 0 || longitude != 0 || radiusMeters != 0) {
            //Enable HereMeNowExtension!
            HereMeNowExtension memory hmne;
            hmne.nowStart = nowStart;
            hmne.nowMinutesDuration = nowMinutesDuration;
            Here memory h;
            h.latitude = latitude;
            h.longitude = longitude;
            h.radiusMeters = radiusMeters;
            hmne.here = h;
            hmne.hereMeNowOnlyAdmins = false;
            hereMeNowOfCollectible[uniqueIdentifier].push(hmne);
        }
    }

    function isAdmin(address addr) private view
    returns (bool addrIsAdmin)
    {
        return admins[addr] == true;
    }

    function royaltiesAreCorrect(address[] royaltyAddresses, uint256[] royaltyAmount) private pure
    returns (bool ok) {
        require(royaltyAddresses.length == royaltyAmount.length);
        return royaltyLessThanTotal(royaltyAmount);
    }

    function royaltyLessThanTotal(uint256[] royalties) private pure
    returns (bool less) {
        uint256 total = 0;
        for (uint256 index = 0; index < royalties.length; index++) {
            total += royalties[index];
        }
        return (total < (100 * PERCENTAGE_MULTIPLIER));
    }

}
pragma solidity ^0.4.20;

contract UnicoCollectible {

    struct Collectible {
        uint256 uniqueIdentifier;
        string name;
        address author;
        uint256 buyPrice;
    }

    function createCollectible(
        uint256 uniqueIdentifier,
        string name,
        address author,
        uint256 buyPrice
        ) public;

    function collectibleExists(uint256 uniqueIdentifier) public view returns (bool exists);
    function getCollectibleBuyPrice(uint256 uniqueIdentifier) public view returns (uint256 price);
    function getCollectibleAuthor(uint256 uniqueIdentifier) public view returns (address author);
}


contract UnicoContract {

    address private constant UNICO_COLLECTIBLE_CONTRACT = 0x0;

    uint private constant PERCENTAGE_MULTIPLIER = 10;

    struct HereMeNowExtension {
        uint256 nowStart;
        uint256 nowMinutesDuration;
        Here here;
        bool hereMeNowOnlyAdmins;
    }

    struct Royalty {
        address user;
        uint256 amount;
    }

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

    mapping(uint256=>uint) public totalSupplyOfCollectible;
    mapping(uint256=>uint) public availableSupplyOfCollectible;

    mapping(address=>uint256[]) public collectiblesOfUser;

    mapping(uint256=>HereMeNowExtension[]) private hereMeNowOfCollectible;
    mapping(uint256=>License[]) private licensesOfCollectible;
    mapping(uint256=>bool) private royaltiesOnSellOfCollectible;

    mapping(uint256=>Royalty[]) public royaltiesOfCollectible;
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

    function UnicoContract() public {
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
        uint256 nowMinutesDuration,
        bool hereMeNowOnlyByAdmins,
        bool royaltiesOnSell
        ) public onlyByAdmins()
    {
        require(initialSupply > 0);
        require(author != address(0x0));
        require(royaltiesAreCorrect(royaltyAddresses, royaltyAmount));
        require(!collectibleExists(uniqueIdentifier));

        createBaseCollectible(uniqueIdentifier, name, author, buyPrice);

        manageRoyalties(uniqueIdentifier, royaltyAddresses, royaltyAmount, royaltiesOnSell);

        manageHereMeNow(uniqueIdentifier,
        nowStart, nowMinutesDuration,
        latitude, longitude, radiusMeters,
        hereMeNowOnlyByAdmins);

        manageSupply(uniqueIdentifier, initialSupply);
    }

    function buyCollectible(uint256 uniqueIdentifierOfCollectible) public payable {
        //Collectible must exists!
        require(collectibleExists(uniqueIdentifierOfCollectible));

        UnicoCollectible uc = UnicoCollectible(UNICO_COLLECTIBLE_CONTRACT);
        if (!isCollectibleAvailable(uniqueIdentifierOfCollectible)) {
            OutOfLicenses();
            revert();
        }
        uint256 buyPrice = uc.getCollectibleBuyPrice(uniqueIdentifierOfCollectible);
        if (msg.value < buyPrice) {
            InsufficientFunds();
            revert();
        }

        License[] storage licenses = licensesOfCollectible[uniqueIdentifierOfCollectible];

        License memory lic;
        lic.collectibleUniqueIdentifier = uniqueIdentifierOfCollectible;
        lic.number = licenses.length + 1;
        lic.owner = msg.sender;
        lic.buyPrice = buyPrice;
        licenses.push(lic);

        availableSupplyOfCollectible[uniqueIdentifierOfCollectible] -= 1;
        collectiblesOfUser[msg.sender].push(uniqueIdentifierOfCollectible);
        usersOfCollectible[uniqueIdentifierOfCollectible].push(msg.sender);

        uint256 totalRoyalties = 0;
        Royalty[] storage royalties = royaltiesOfCollectible[uniqueIdentifierOfCollectible];
        for (uint256 index = 0; index < royalties.length; index++) {
            uint256 royalty = royalties[index].amount * buyPrice / (100 * PERCENTAGE_MULTIPLIER);
            totalRoyalties += royalty;
            royalties[index].user.transfer(royalty);
        }
        uc.getCollectibleAuthor(uniqueIdentifierOfCollectible).transfer(buyPrice - totalRoyalties);
        if (msg.value > buyPrice) {
            msg.sender.transfer(msg.value - buyPrice);
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
        uint256 totalRoyalties = 0;
        if (royaltiesOnSellOfCollectible[uniqueIdentifierOfCollectible]) {
            Royalty[] storage royalties = royaltiesOfCollectible[uniqueIdentifierOfCollectible];
            for (uint256 index = 0; index < royalties.length; index++) {
                uint256 royalty = royalties[index].amount * opt.price / (100 * PERCENTAGE_MULTIPLIER);
                totalRoyalties += royalty;
                royalties[index].user.transfer(royalty);
            }
        }
        lic.owner.transfer(msg.value - totalRoyalties);
    }

    function setRoyaltiesOnSellForCollectible(uint256 uniqueIdentifierOfCollectible, bool royaltiesOnSell)
    public onlyByAdmins()
    {
        royaltiesOnSellOfCollectible[uniqueIdentifierOfCollectible] = royaltiesOnSell;
    }

    function emitFreeLicenseToRoyaltiesOwners(uint256 uniqueIdentifierOfCollectible) public onlyByAdmins() {
        require(collectibleExists(uniqueIdentifierOfCollectible));

        Royalty[] storage royalties = royaltiesOfCollectible[uniqueIdentifierOfCollectible];
        for (uint256 index = 0; index < royalties.length; index++) {
            emitFreeLicenses(uniqueIdentifierOfCollectible, royalties[index].user);
        }
    }

    function emitFreeLicenses(uint256 uniqueIdentifierOfCollectible, address receiver) public onlyByAdmins() {
        require(collectibleExists(uniqueIdentifierOfCollectible));

        if (availableSupplyOfCollectible[uniqueIdentifierOfCollectible] == 0) {
            OutOfLicenses();
            revert();
        }

        License[] storage licenses = licensesOfCollectible[uniqueIdentifierOfCollectible];

        License memory lic;
        lic.collectibleUniqueIdentifier = uniqueIdentifierOfCollectible;
        lic.number = licenses.length + 1;
        lic.owner = receiver;
        lic.buyPrice = 0;
        licenses.push(lic);

        availableSupplyOfCollectible[uniqueIdentifierOfCollectible] -= 1;
        collectiblesOfUser[receiver].push(uniqueIdentifierOfCollectible);
        usersOfCollectible[uniqueIdentifierOfCollectible].push(receiver);
    }

    function signHereMeNow(
        uint256 uniqueIdentifierOfCollectible,
        uint256 licenseNumber,
        uint256 latitude,
        uint256 longitude,
        address signer,
        uint256 timestamp
        ) public {
        License storage lic = licensesOfCollectible[uniqueIdentifierOfCollectible][licenseNumber];
        HereMeNowExtension[] storage hmn = hereMeNowOfCollectible[uniqueIdentifierOfCollectible];
        for (uint256 index = 0; index < hmn.length; index++) {
            signHereMeNowLicense(
                lic,
                hmn[index],
                latitude,
                longitude,
                signer,
                timestamp);
        }
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

    function manageRoyalties(uint256 uniqueIdentifier, address[] royaltyAddresses, uint256[] royaltyAmount,
    bool royaltiesOnSell)
    private {
        if (royaltyAddresses.length > 0) {
            Royalty[] storage royalties = royaltiesOfCollectible[uniqueIdentifier];
            for (uint index = 0; index < royaltyAddresses.length; index++) {
                royalties.push(Royalty(royaltyAddresses[index], royaltyAmount[index]));
            }
        }
        royaltiesOnSellOfCollectible[uniqueIdentifier] = royaltiesOnSell;
    }

    function manageHereMeNow(
        uint256 uniqueIdentifier,
        uint256 nowStart,
        uint256 nowMinutesDuration,
        uint256 latitude,
        uint256 longitude,
        uint256 radiusMeters,
        bool hereMeNowOnlyByAdmins) private {
        if (nowStart > 0 || latitude != 0 || longitude != 0 || radiusMeters != 0) {
            HereMeNowExtension memory hmne;
            hmne.nowStart = nowStart;
            hmne.nowMinutesDuration = nowMinutesDuration;
            Here memory h;
            h.latitude = latitude;
            h.longitude = longitude;
            h.radiusMeters = radiusMeters;
            hmne.here = h;
            hmne.hereMeNowOnlyAdmins = hereMeNowOnlyByAdmins;
            hereMeNowOfCollectible[uniqueIdentifier].push(hmne);
        }
    }

    function signHereMeNowLicense(
        License lic,
        HereMeNowExtension hmne,
        uint256 latitude,
        uint256 longitude,
        address signer,
        uint256 timestamp) private {
        if (hmne.hereMeNowOnlyAdmins) {
            require(isAdmin(msg.sender));
        }
        HereMeNow memory hmn;
        lic.hereMeNow = hmn;

        hmn.here.latitude = latitude;
        hmn.here.longitude = longitude;
        hmn.me = signer;
        hmn.timestamp = timestamp;

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

    function collectibleExists(uint256 uniqueIdentifier) private view
    returns (bool exists) {
        UnicoCollectible uc = UnicoCollectible(UNICO_COLLECTIBLE_CONTRACT);
        return uc.collectibleExists(uniqueIdentifier);
    }

    function isCollectibleAvailable(uint256 uniqueIdentifier) private view
    returns (bool available) {
        return availableSupplyOfCollectible[uniqueIdentifier] > 0;
    }

    function createBaseCollectible(
        uint256 uniqueIdentifier,
        string name,
        address author,
        uint256 buyPrice
        ) private {
        UnicoCollectible uc = UnicoCollectible(UNICO_COLLECTIBLE_CONTRACT);
        uc.createCollectible(uniqueIdentifier, name, author, buyPrice);
    }

    function manageSupply(uint256 uniqueIdentifier, uint256 initialSupply) private {
        totalSupplyOfCollectible[uniqueIdentifier] = initialSupply;
        availableSupplyOfCollectible[uniqueIdentifier] = initialSupply;
    }

}
pragma solidity ^0.4.20;


contract UnicoCollectible {

    struct Collectible {
        uint256 uniqueIdentifier;
        string name;
        address author;
        uint256 buyPrice;
    }

    mapping(address=>bool) private admins;
    uint256 private adminsCount;

    Collectible[] public collectibles;
    mapping(uint256=>Collectible) public collectibleList;

    modifier onlyByAdmins() {
        require(isAdmin(msg.sender));
        _;
    }

    function UnicoCollectible() public {
        admins[msg.sender] = true;
        adminsCount += 1;
    }

    function createCollectible(
        uint256 uniqueIdentifier,
        string name,
        address author,
        uint256 buyPrice
        ) public onlyByAdmins()
    {
        require(author != address(0x0));
        require(!collectibleExists(uniqueIdentifier));

        Collectible memory c;
        c.uniqueIdentifier = uniqueIdentifier;
        c.name = name;
        c.author = author;
        c.buyPrice = buyPrice;

        collectibles.push(c);
        collectibleList[c.uniqueIdentifier] = c;
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

    function getCollectibleBuyPrice(uint256 uniqueIdentifier) public view
    returns (uint256 price) {
        return collectibleList[uniqueIdentifier].buyPrice;
    }

    function getCollectibleAuthor(uint256 uniqueIdentifier) public view
    returns (address author) {
        return collectibleList[uniqueIdentifier].author;
    }

    function collectibleExists(uint256 uniqueIdentifier) public view
    returns (bool exists) {
        return collectibleList[uniqueIdentifier].uniqueIdentifier == uniqueIdentifier;
    }

    function isAdmin(address addr) private view
    returns (bool addrIsAdmin)
    {
        return admins[addr] == true;
    }

}
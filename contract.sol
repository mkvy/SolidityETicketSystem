// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

contract ETicketSystem {
    address public owner;

    // Мероприятие
    struct Event {
        uint256 eventId; // id
        string name; // Название
        uint time; // Время мероприятия
        address owner; // Создатель мероприятия
        EventStatus status; // Статус мероприятия (Запланировано, Отменено, Закончено)
    }

    enum EventStatus { Scheduled, Cancelled, Finished }

    enum TicketStatus { Available, Sold, Withdrawed, Not_Available }

    // Билет
    struct Ticket {
        uint256 id; // id
        string uuid; // uuid
        uint256 eventId; // id мероприятия
        address creatorAddress; // адрес продавца-создателя билета
        address ownerAddress; // адрес владельца
        uint256 price; // цена
        string metaInformation; // мета-информация (номер места и т.д.)
        TicketStatus status; // статус. (Доступен для покупки, Продан, Обналичен, Недоступен)
        uint purchaseTime; // время покупки
    }

    mapping(uint256 => Ticket) public tickets; // мапа созданых билетов
    mapping(uint256 => Event) public events; // мапа созданных мероприятий
    mapping(address => uint256[]) public soldTickets; // мапа проданных билетов для каждого продавца (для удобного поиска)
    mapping(string => bool) public uuidExists; // вспомогательная мапа для uuid

    uint256 public ticketCounter; // глобальная переменная-счетчик билетов
    uint256 public eventCounter; // глобальная переменная-счетчик мероприятий


    event EventCreated(uint256 indexed eventId, string name, address owner, uint256 time, EventStatus status);
    event TicketCreated(uint256 indexed ticketId, string uuid, uint256 eventId, uint256 price, string metaInformation, address owner);
    event TicketPurchased(uint256 ticketId, string eventName, address buyer);
    event TicketTransferred(uint256 ticketId, address from, address to);
    event TicketRefunded(uint256 ticketId, address refundedTo);
    event FundsWithdrawn(address indexed owner, uint256 totalFund);
    event EventStatusChanged(uint256 indexed eventId,EventStatus oldStatus,EventStatus newStatus);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only the owner can call this function");
        _;
    }

    // структуры и код для добавления прав "администратора" пользователям
    mapping(address => bool) public admins;

    event AdminAdded(address indexed admin);
    event AdminRemoved(address indexed admin);

    modifier onlyAdmin() {
        require(isAdmin(msg.sender), "Unauthorized: Only admins can call this function");
        _;
    }

    modifier onlyOwnerOrAdmin() {
        require(msg.sender == owner || isAdmin(msg.sender), "Unauthorized: Caller is not the owner or admin");
        _;
    }
    
    modifier ticketExists(uint256 ticketId) {
        require(ticketId <= ticketCounter, "Ticket does not exist");
        _;
    }

    modifier ticketNotSold(uint256 ticketId) {
        require(tickets[ticketId].status == TicketStatus.Available, "Ticket has already been sold or transferred");
        _;
    }

     modifier eventExists(string memory eventName) {
        require(getEventIdByName(eventName) != 0, "Event does not exists");
        _;
    }
     modifier onlyEventOwner(uint256 eventId) {
        require(events[eventId].owner == msg.sender, "Caller is not an owner of event");
        _;
     }

     modifier ticketIsSold(uint256 ticketId) {
        require(tickets[ticketId].status == TicketStatus.Sold, "Ticket is not sold");
        _;
    }
    modifier ticketOwner(uint256 ticketId) {
        require(msg.sender == tickets[ticketId].ownerAddress, "Only the owner can transfer the ticket");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function addAdmin(address _admin) external onlyOwner {
        admins[_admin] = true;
        emit AdminAdded(_admin);
    }

    function removeAdmin(address _admin) external onlyOwner {
        admins[_admin] = false;
        emit AdminRemoved(_admin);
    }

    function isAdmin(address _address) internal view returns (bool) {
        return admins[_address];
    }

    function generateUUID() internal view returns (string memory) {
        bytes32 uuidHash = keccak256(abi.encodePacked(block.timestamp, msg.sender, ticketCounter));
        return toString(uuidHash);
    }

    function toString(bytes32 _bytes32) internal pure returns (string memory) {
        bytes memory bytesArray = new bytes(32);
        for (uint256 i = 0; i < 32; i++) {
            bytesArray[i] = _bytes32[i];
        }
        return string(bytesArray);
    }

    // создание мероприятия. доступно либо создателю контракта, либо аккаунту с админскими правами.
    function createEvent(string memory _eventName,
    uint _eventTime) external 
    onlyOwnerOrAdmin returns (uint256) {
        eventCounter++;
        events[eventCounter] = Event({
            eventId: eventCounter,
            name: _eventName,
            time: _eventTime,
            owner: msg.sender,
            status: EventStatus.Scheduled
        });
        emit EventCreated(eventCounter,_eventName,
        msg.sender,_eventTime,EventStatus.Scheduled);
        return eventCounter;
    }

    // создание билета. доступно либо создателю контракта, либо аккаунту с админскими правами.
    function createTicket(uint256 _eventId,
    uint256 _price,
    string memory _metaInformation) external onlyOwnerOrAdmin returns (uint256) {
        uint256 eventStartTime = events[_eventId].time;
        require(eventStartTime >= block.timestamp, "Event has already started");
        require(events[_eventId].status == EventStatus.Scheduled, "Event is finished or cancelled");

        ticketCounter++;
        string memory uuid = generateUUID();

        require(!uuidExists[uuid], "UUID already exists");
        uuidExists[uuid] = true;

        tickets[ticketCounter] = Ticket({
            id: ticketCounter,
            uuid: uuid,
            eventId: _eventId,
            creatorAddress: msg.sender,
            ownerAddress: msg.sender,
            price: _price,
            metaInformation: _metaInformation,
            status: TicketStatus.Available,
            purchaseTime: 0
        });
        emit TicketCreated(ticketCounter, uuid, 
        _eventId, _price, _metaInformation, msg.sender);
        return ticketCounter;
    }

    // создание билетов (массовое). доступно либо создателю контракта, либо аккаунту с админскими правами.
    function createBatchTickets(uint256 _eventId,
    uint256 _price,string[] memory _metaInformation) external onlyOwnerOrAdmin {
        uint256 eventStartTime = events[_eventId].time;

        require(eventStartTime >= block.timestamp, "Event has already started");
        require(events[_eventId].status == EventStatus.Scheduled, "Event is finished or cancelled");
        require(_metaInformation.length > 0, "Batch creation requires at least one metaInformation");

        for (uint256 i = 0; i < _metaInformation.length; i++) {
            ticketCounter++;
            string memory uuid = generateUUID();

            require(!uuidExists[uuid], "UUID already exists");
            uuidExists[uuid] = true;

            tickets[ticketCounter] = Ticket({
                id: ticketCounter,
                uuid: uuid,
                eventId: _eventId,
                creatorAddress: msg.sender,
                ownerAddress: msg.sender,
                price: _price,
                metaInformation: _metaInformation[i],
                status: TicketStatus.Available,
                purchaseTime: 0
            });

            emit TicketCreated(ticketCounter, uuid, _eventId, _price, _metaInformation[i], msg.sender);
        }
    }

    // смена статуса мероприятия. доступно создателю мероприятия
    function changeEventStatus(uint256 eventId, EventStatus newStatus) external onlyEventOwner(eventId) {
        require(eventId > 0 && eventId <= eventCounter, "Invalid event ID");
        if (newStatus == EventStatus.Cancelled) {
            cancelEventRefund(eventId);
        }
        EventStatus oldStatus = events[eventId].status;
        events[eventId].status = newStatus;
        emit EventStatusChanged(eventId, oldStatus, newStatus);
    }
    
    // в случае отмены мероприятия, возврат средств владельцам
    function cancelEventRefund(uint256 eventId) internal onlyEventOwner(eventId) {
            for (uint256 i = 1; i <= ticketCounter; i++) {
            Ticket storage ticket = tickets[i];
            if (ticket.eventId == eventId && ticket.status == TicketStatus.Sold) {
                        payable(ticket.ownerAddress).transfer(ticket.price);
                        ticket.status = TicketStatus.Not_Available;
                        ticket.ownerAddress = address(0);
            }
        }        
    }
    
    // покупка билетов 
    function purchaseTicket(uint256 ticketId) 
    external payable ticketExists(ticketId) ticketNotSold(ticketId) {
        require(msg.value >= tickets[ticketId].price, "Incorrect amount sent for ticket purchase");
        require(msg.sender != tickets[ticketId].ownerAddress, "Owner cannot purchase their own ticket");
        require(block.timestamp < events[tickets[ticketId].eventId].time, "Event has already started");
        tickets[ticketId].ownerAddress = msg.sender;
        tickets[ticketId].status = TicketStatus.Sold;
        tickets[ticketId].purchaseTime = block.timestamp;
        soldTickets[tickets[ticketId].creatorAddress].push(ticketId);

        if (msg.value - tickets[ticketId].price > 0) {
            //return extra
            payable(msg.sender).transfer(msg.value - tickets[ticketId].price);
        }
        emit TicketPurchased(ticketId, events[tickets[ticketId].eventId].name, msg.sender);
    }

    // покупка самого дешевого билета по названию мероприятия
    function purchaseTicketByEventName(string calldata _eventName) 
    external payable eventExists(_eventName) returns (uint256) {        
        uint256 ticketId = findCheapestTicketId(_eventName);
        require(msg.value >= tickets[ticketId].price, "Incorrect amount sent for ticket purchase");
        require(msg.sender != owner, "Owner cannot purchase their own ticket");
        require(block.timestamp < events[tickets[ticketId].eventId].time, "Event has already started");

        tickets[ticketId].ownerAddress = msg.sender;
        tickets[ticketId].status = TicketStatus.Sold;
        tickets[ticketId].purchaseTime = block.timestamp;

        if (msg.value - tickets[ticketId].price > 0) {
            //return extra
            payable(msg.sender).transfer(msg.value - tickets[ticketId].price);
        }
        emit TicketPurchased(ticketId, _eventName, msg.sender);
        return ticketId;
    }

    // вспомогательные функции для поиска ивента по id
    function getEventIdByName(string memory _eventName) internal view returns (uint256) {
        for (uint256 i = 1; i <= eventCounter; i++) {
            if (keccak256(abi.encodePacked(events[i].name)) == keccak256(abi.encodePacked(_eventName))) {
                return i;
            }
        }
        return 0; // Event not found
    }
    // поиск самого дешевого билета на мероприятие
    function findCheapestTicketId(string calldata _eventName) internal view returns (uint256) {
        uint256 cheapestPrice = type(uint256).max;
        uint256 cheapestTicketId;
        uint256 eventId = getEventIdByName(_eventName);
        for (uint256 i = 1; i <= ticketCounter; i++) {
            Ticket storage ticket = tickets[i];
            if (ticket.eventId == eventId && ticket.status == TicketStatus.Available &&
                ticket.price < cheapestPrice) {
                cheapestPrice = ticket.price;
                cheapestTicketId = i;
            }
        }

        if (cheapestTicketId == 0) {
            revert("No available tickets found for the specified event");
        }

        return cheapestTicketId;
    }

    // передача билетов другому пользователю
    function transferTicket(uint256 ticketId, address to) 
    external ticketOwner(ticketId) ticketExists(ticketId) ticketIsSold(ticketId) {
        require(block.timestamp < events[tickets[ticketId].eventId].time, "Event has already started");
        tickets[ticketId].ownerAddress = to;
        emit TicketTransferred(ticketId, msg.sender, to);
    }

    // возврат билета
    function refundTicket(uint256 ticketId) external ticketOwner(ticketId) ticketExists(ticketId) {
        require(events[tickets[ticketId].eventId].status == EventStatus.Scheduled 
        || block.timestamp < events[tickets[ticketId].eventId].time, "Cannot refund. Event is already finished or started");
        require(tickets[ticketId].status == TicketStatus.Sold, "ticket is not bought");

        payable(tickets[ticketId].ownerAddress).transfer(tickets[ticketId].price);

        tickets[ticketId].status = TicketStatus.Available;
        tickets[ticketId].ownerAddress = address(0);
        deleteTicketIdFromSoldTickets(tickets[ticketId].creatorAddress,ticketId);

        emit TicketRefunded(ticketId, msg.sender);
    }
    
    // удаление билета из списка проданных билетов
    function deleteTicketIdFromSoldTickets(address ownerAddress, uint256 ticketId) internal {
        uint256[] storage ownerTicketList = soldTickets[ownerAddress];
        for (uint256 i = 0; i < ownerTicketList.length; i++) {
            if (ownerTicketList[i] == ticketId) {
                ownerTicketList[i] = ownerTicketList[ownerTicketList.length - 1];
                ownerTicketList.pop();
                break;
            }
        }
    }

    // возврат адреса владельца билета по его ID
    function getTicketOwnerAddress(uint256 ticketId) view external ticketExists(ticketId) returns (address)  {
            return tickets[ticketId].ownerAddress;
    }
    
    // снятие денег с баланса контракта с проданных билетов
    function withdrawFunds() external onlyOwnerOrAdmin {
        uint256[] storage ticketIds = soldTickets[msg.sender];
        uint256 totalFund;
        for (uint256 i = 0; i < ticketIds.length; i++) {
            uint256 ticketId = ticketIds[i];

            // Check if the ticket is sold and not refunded
            if (tickets[ticketId].status == TicketStatus.Sold 
            && events[tickets[ticketId].eventId].status == EventStatus.Finished) {
                totalFund += tickets[ticketId].price;
                tickets[ticketId].status = TicketStatus.Withdrawed;
                tickets[ticketId].ownerAddress = address(0);
                deleteTicketIdFromSoldTickets(msg.sender, ticketId);
            }
        }
        require(totalFund > 0, "No funds to withdraw");
        // Transfer the total refund amount from the contract balance to the ticket owner
        payable(msg.sender).transfer(totalFund);
        emit FundsWithdrawn(msg.sender, totalFund);
    }
}

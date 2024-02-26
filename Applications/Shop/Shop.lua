local event = require("event")
local c = require("component")
local unicode = require("unicode")
local sides = require("sides")
local gpu = c.gpu
local inv = c.inventory_controller
local chestSide = sides.up

--------------------------------------------------------------------------------------------------------

local currentMode = 3
local xSize, ySize = gpu.getResolution()

local rarityColors = {
	["Common"] = 0xB0C3D9,
	["Uncommon"] = 0x5E98D9,
	["Rare"] = 0x4B69FF,
	["Mythical"] = 0x8847FF,
	["Legendary"] = 0xD32CE6,
	["Immortal"] = 0xE4AE33,
	["Arcana"] = 0xADE55C,
	["Ancient"] = 0xEB4B4B
}

local colors = {
	["background"] = 0x262626,
	["topbar"] = 0xffffff,
	["topbarText"] = 0x444444,
	["topbarButton"] = ecs.colors.blue,
	["topbarButtonText"] = 0xffffff,
	["inventoryBorder"] =  0xffffff,
	["inventoryBorderSelect"] = ecs.colors.blue,
	["inventoryBorderSelectText"] = 0xffffff,
	["inventoryText"] = 0x262626,
	["inventoryTextDarker"] = 0x666666,
	["sellButtonColor"] = ecs.colors.blue,
	["sellButtonTextColor"] = 0xffffff,
}

local moneySymbol = "€"
local adminSellMultiplyer = 0.5

local widthOfOneItemElement = 12
local heightOfOneItemElement = widthOfOneItemElement / 2

--------------------------------------------------------------------------------------------------------

local adminShop = {
	["minecraft:stone"] = {
		["data"] = 0,
		["price"] = 4,
		["rarity"] = "Uncommon",
	},
	["minecraft:diamond"] = {
		["data"] = 0,
		["price"] = 200,
		["rarity"] = "Legendary",
	},
	["minecraft:grass"] = {
		["data"] = 0,
		["price"] = 4,
		["rarity"] = "Uncommon",
	},
	["minecraft:cobblestone"] = {
		["data"] = 0,
		["price"] = 2,
		["rarity"] = "Common",
	},
	["minecraft:dirt"] = {
		["data"] = 0,
		["price"] = 2,
		["rarity"] = "Common",
	},
	["minecraft:iron_ore"] = {
		["data"] = 0,
		["price"] = 20,
		["rarity"] = "Rare",
	},
	["minecraft:gold_ore"] = {
		["data"] = 0,
		["price"] = 40,
		["rarity"] = "Mythical",
	},
	["minecraft:coal_ore"] = {
		["data"] = 0,
		["price"] = 5,
		["rarity"] = "Uncommon",
	},
	["minecraft:wool"] = {
		["data"] = 0,
		["price"] = 10,
		["rarity"] = "Uncommon",
	},
	["minecraft:redstone"] = {
		["data"] = 0,
		["price"] = 10,
		["rarity"] = "Rare",
	},
	["minecraft:log"] = {
		["data"] = 0,
		["price"] = 3,
		["rarity"] = "Common",
	},
	["IC2:itemOreIridium"] = {
		["data"] = 0,
		["price"] = 50000,
		["rarity"] = "Arcana",
	},
}

local massivWithProfile = {
	["name"] = "IT",
	["money"] = 1000000,
	["inventory"] = {
		{
			["id"] = "minecraft:stone",
			["label"] = "Stone",
			["data"] = 0,
			["count"] = 64,
		},
		{
			["id"] = "minecraft:grass",
			["data"] = 0,
			["label"] = "Grass",
			["count"] = 32,
		},
		{
			["id"] = "minecraft:wool",
			["data"] = 0,
			["label"] = "Red wool",
			["count"] = 12,
		},
		{
			["id"] = "minecraft:diamond",
			["data"] = 0,
			["label"] = "Diamond",
			["count"] = 999,
		},
		{
			["id"] = "minecraft:cobblestone",
			["data"] = 0,
			["label"] = "Cobblestone",
			["count"] = 47000,
		},
		{
			["id"] = "minecraft:redstone",
			["data"] = 0,
			["label"] = "Redstone",
			["count"] = 12000,
		},
		{
			["id"] = "minecraft:iron_ore",
			["data"] = 0,
			["label"] = "Iron ore",
			["count"] = 572,
		},
		{
			["id"] = "minecraft:gold_ore",
			["data"] = 0,
			["label"] = "Gold ore",
			["count"] = 246,
		},
		{
			["id"] = "minecraft:coal_ore",
			["data"] = 0,
			["label"] = "Coal ore",
			["count"] = 11,
		},
		{
			["id"] = "IC2:itemOreIridium",
			["data"] = 0,
			["label"] = "Iridium Ore",
			["count"] = 5,
		},
		{
			["id"] = "minecraft:log",
			["data"] = 0,
			["label"] = "Log",
			["count"] = 124782,
		},
	},
}

--Обжекты
local obj = {}
local function newObj(class, name, ...)
	obj[class] = obj[class] or {}
	obj[class][name] = {...}
end

--Сконвертировать кол-во предметов в более компактный вариант
local function prettyItemCount(count)
	if count >= 1000 then
		return tostring(math.floor(count / 1000)) .. "K"
	end
	return tostring(count)
end

--Добавление предмета в инвентарь
local function addItemToInventory(id, data, label, count)
	--Переменная успеха, означающая, что такой предмет уже есть,
	--и что его количество успешно увеличилось
	local success = false
	--Перебираем весь массив инвентаря и смотрим, есть ли чет такое
	for i = 1, #massivWithProfile.inventory do
		if id == massivWithProfile.inventory[i].id then
			if data == massivWithProfile.inventory[i].data then
				massivWithProfile.inventory[i].count = massivWithProfile.inventory[i].count + count
				success = true
				break
			end
		end
	end

	--Если такого предмета нет, то создать новый слот в инвентаре
	if not success then
		table.insert(massivWithProfile.inventory, { ["id"] = id, ["data"] = data, ["label"] = label, ["count"] = count } )
	end
end

--Удалить кол-во предмета из инвентаря
local function removeItemFromInventory(numberOfItemInInventory, count)
	local skokaMozhnaUdalit = massivWithProfile.inventory[numberOfItemInInventory].count
	if count > skokaMozhnaUdalit then count = skokaMozhnaUdalit end
	massivWithProfile.inventory[numberOfItemInInventory].count = massivWithProfile.inventory[numberOfItemInInventory].count - count
	if massivWithProfile.inventory[numberOfItemInInventory].count == 0 then
		table.remove(massivWithProfile.inventory, numberOfItemInInventory)
	end
end

--Просканировать сундук и добавить в него шмот
local function addToInventoryFromChest()
	local counter = 0
	local inventorySize = inv.getInventorySize(chestSide)
	for i = 1, inventorySize do
		local stack = inv.getStackInSlot(chestSide, i)
		if stack then
			addItemToInventory(stack.name, stack.damage, stack.label, stack.size)
			counter = counter + stack.size
		end
	end

	return counter
end

--Продать шмотку одменам
local function sellToAdmins(numberOfItemInInventory, skoka)
	local item = massivWithProfile.inventory[numberOfItemInInventory]
	if adminShop[item.id] then
		local price = math.floor(adminShop[item.id].price * adminSellMultiplyer)
		removeItemFromInventory(numberOfItemInInventory, skoka)
		massivWithProfile.money = massivWithProfile.money + price * skoka
		return (price * skoka)
	end
	return 0
end

--Нарисовать конкретный айтем
local function drawItem(xPos, yPos, back, fore, text1, text2)
	--Рисуем квадратик
	ecs.square(xPos, yPos, widthOfOneItemElement, heightOfOneItemElement, back)
	--Рисуем текст в рамке
	text1 = ecs.stringLimit("end", text1, widthOfOneItemElement - 2)
	text2 = ecs.stringLimit("end", prettyItemCount(text2), widthOfOneItemElement - 2)
	local x
	x = xPos + math.floor(widthOfOneItemElement / 2 - unicode.len(text1) / 2)
	ecs.colorText(x, yPos + 2, fore, text1)
	x = xPos + math.floor(widthOfOneItemElement / 2 - unicode.len(text2) / 2)
	ecs.colorText(x, yPos + 3, fore, text2)
	x = nil
end

--Показ инвентаря
local function showInventory(x, y, massivOfInventory, page, currentItem)
	obj["SellItems"] = nil
	obj["SellButtons"] = nil

	local widthOfItemInfoPanel = 26
	local width = math.floor((xSize - widthOfItemInfoPanel - 4) / (widthOfOneItemElement))
	local height = math.floor((ySize - 8) / (heightOfOneItemElement))
	local countOfItems = #massivOfInventory.inventory
	local countOfPages = math.ceil(countOfItems / (width * height))
	local widthOfAllElements = width * widthOfOneItemElement
	local heightOfAllElements = height * heightOfOneItemElement
	currentItem = currentItem or 1

	--Очищаем фоном
	ecs.square(x, y, widthOfAllElements, heightOfAllElements, colors.background)

	--Рисуем айтемы
	local textColor, borderColor, itemCounter, xPos, yPos = nil, nil, 1 + page * width * height - width * height, x, y
	for j = 1, height do
		xPos = x
		for i = 1, width do
			--Если такой предмет вообще существует
			if massivOfInventory.inventory[itemCounter] then
				--Делаем цвет рамки
				if itemCounter == currentItem then
					borderColor = colors.inventoryBorderSelect
					textColor = colors.inventoryBorderSelectText
				else
					local cyka = false
					if j % 2 == 0 then
						if i % 2 ~= 0 then
							cyka = true
						end
					else
						if i % 2 == 0 then
							cyka = true
						end
					end

					if cyka then
						borderColor = colors.inventoryBorder
					else
						borderColor = colors.inventoryBorder - 0x111111
					end
					textColor = colors.inventoryText
				end

				--Рисуем итем
				drawItem(xPos, yPos, borderColor, textColor, massivOfInventory.inventory[itemCounter].label, massivOfInventory.inventory[itemCounter].count)
			
				newObj("SellItems", itemCounter, xPos, yPos, xPos + widthOfOneItemElement - 1, yPos + heightOfOneItemElement - 1)
			else
				break
			end

			itemCounter = itemCounter + 1

			xPos = xPos + widthOfOneItemElement
		end
		yPos = yPos + heightOfOneItemElement
	end

	--Рисуем инфу о кнкретном айтеме
	xPos = x + widthOfAllElements + 2
	yPos = y
	widthOfItemInfoPanel = xSize - xPos - 1
	
	--Рамку рисуем
	ecs.square(xPos, yPos, widthOfItemInfoPanel, ySize - 5, colors.inventoryBorder)
	yPos = yPos + 1
	xPos = xPos + 2
	
	--Инфа о блоке
	local currentRarity = adminShop[massivOfInventory.inventory[currentItem].id]
	if not currentRarity then currentRarity = "Common" else currentRarity = currentRarity.rarity end
	ecs.colorText(xPos, yPos, colors.inventoryText, massivOfInventory.inventory[currentItem].label); yPos = yPos + 1
	ecs.colorText(xPos, yPos, rarityColors[currentRarity], currentRarity); yPos = yPos + 1
	ecs.colorText(xPos, yPos, colors.inventoryTextDarker, massivOfInventory.inventory[currentItem].id); yPos = yPos + 1
	ecs.colorText(xPos, yPos, colors.inventoryTextDarker, "Цвет: " .. massivOfInventory.inventory[currentItem].data); yPos = yPos + 1
	ecs.colorText(xPos, yPos, colors.inventoryTextDarker, "Количество: " .. massivOfInventory.inventory[currentItem].count); yPos = yPos + 1

	--Твой бабос
	yPos = yPos + 1
	ecs.colorText(xPos, yPos, colors.inventoryText, "Твой капитал:"); yPos = yPos + 1
	ecs.colorText(xPos, yPos, colors.inventoryTextDarker, massivOfInventory.money .. moneySymbol); yPos = yPos + 1
	
	--Цена админов
	yPos = yPos + 1
	local adminPrice = adminShop[massivOfInventory.inventory[currentItem].id]
	if adminPrice then adminPrice = math.floor(adminPrice.price * adminSellMultiplyer) .. moneySymbol else adminPrice = "Отсутствует" end
	ecs.colorText(xPos, yPos, colors.inventoryText, "Цена у админов:"); yPos = yPos + 1
	ecs.colorText(xPos, yPos, colors.inventoryTextDarker, adminPrice)

	--Цена на ТП
	yPos = yPos + 2
	ecs.colorText(xPos, yPos, colors.inventoryText, "Цена на Торговой Площадке:"); yPos = yPos + 1
	ecs.colorText(xPos, yPos, colors.inventoryTextDarker, "От 130.27"..moneySymbol); yPos = yPos + 1

	--Кнопы
	xPos = xPos - 2
	yPos = ySize - 3
	local x1, y1, x2, y2, name
	name = "Продать игрокам"; x1, y1, x2, y2 = ecs.drawButton(xPos, yPos, widthOfItemInfoPanel, 3, name, colors.sellButtonColor, colors.sellButtonTextColor); newObj("SellButtons", name, x1, y1, x2, y2, widthOfItemInfoPanel); yPos = yPos - 3
	if adminPrice ~= "Отсутствует" then
		name = "Продать админам"; x1, y1, x2, y2 = ecs.drawButton(xPos, yPos, widthOfItemInfoPanel, 3, name, 0x66b6ff, colors.sellButtonTextColor); newObj("SellButtons", name, x1, y1, x2, y2, widthOfItemInfoPanel); yPos = yPos - 3
	end
	name = "Пополнить инвентарь"; x1, y1, x2, y2 = ecs.drawButton(xPos, yPos, widthOfItemInfoPanel, 3, name, 0x99dbff, colors.sellButtonTextColor); newObj("SellButtons", name, x1, y1, x2, y2, widthOfItemInfoPanel); yPos = yPos - 3

	--Перелистывалки
	local stro4ka = tostring(page) .. " из " .. tostring(countOfPages)
	local sStro4ka = unicode.len(stro4ka) + 2
	xPos = xPos - sStro4ka - 16
	yPos = ySize - 3
	name = "<"; x1, y1, x2, y2 = ecs.drawButton(xPos, yPos, 7, 3, name, colors.sellButtonColor, colors.sellButtonTextColor); newObj("SellButtons", name, x1, y1, x2, y2, 7); xPos = xPos + 7
	ecs.square(xPos, yPos, sStro4ka, 3, colors.inventoryBorder)
	ecs.colorText(xPos + 1, yPos + 1, 0x000000, stro4ka); xPos = xPos + sStro4ka
	name = ">"; x1, y1, x2, y2 = ecs.drawButton(xPos, yPos, 7, 3, name, colors.sellButtonColor, colors.sellButtonTextColor); newObj("SellButtons", name, x1, y1, x2, y2, 7)

	return countOfPages
end

local function sell()
	--Показываем инвентарь
	local xInventory, yInventory, currentPage, currentItem = 3, 5, 1, 1
	local countOfPages = showInventory(xInventory, yInventory, massivWithProfile, currentPage, currentItem)

ecs.error("Программа разрабатывается. По сути это будет некий аналог Торговой Площадки Стима с разными доп. фичами.")


	while true do
		local e = {event.pull()}
		if e[1] == "touch" then
			for key in pairs(obj["SellItems"])do
				if ecs.clickedAtArea(e[3], e[4], obj["SellItems"][key][1], obj["SellItems"][key][2], obj["SellItems"][key][3], obj["SellItems"][key][4]) then
					currentItem = key
					showInventory(xInventory, yInventory, massivWithProfile, currentPage, currentItem)
					break
				end
			end

			for key in pairs(obj["SellButtons"])do
				if ecs.clickedAtArea(e[3], e[4], obj["SellButtons"][key][1], obj["SellButtons"][key][2], obj["SellButtons"][key][3], obj["SellButtons"][key][4]) then
					ecs.drawButton(obj["SellButtons"][key][1], obj["SellButtons"][key][2], obj["SellButtons"][key][5], 3, key, ecs.colors.green, 0xffffff)
					os.sleep(0.3)

					if key == ">" then
						if currentPage < countOfPages then currentPage = currentPage + 1 end
					
					elseif key == "<" then
						if currentPage > 1 then currentPage = currentPage - 1 end
					
					elseif key == "Пополнить инвентарь" then
						ecs.error("Пихай предметы в сундук и жми ок, епта!")
						local addedCount = addToInventoryFromChest()
						ecs.error("Добавлено "..addedCount.." предметов.")
					
					elseif key == "Продать админам" then
						local maxToSell = massivWithProfile.inventory[currentItem].count
						local data = ecs.universalWindow("auto", "auto", 40, 0x444444, true, {"EmptyLine"}, {"CenterText", 0xffffff, "Сколько продаем?"}, {"EmptyLine"}, {"Slider", 0xffffff, 0x33db80, 1, maxToSell, math.floor(maxToSell / 2), "Количество: "}, {"EmptyLine"}, {"Button", 0x33db80, 0xffffff, "Продать"})
						local count = data[1] or nil
						if count then
							local money = sellToAdmins(currentItem, count)
							ecs.universalWindow("auto", "auto", 40, 0x444444, true, {"EmptyLine"}, {"CenterText", 0xffffff, "Успешно продано!"}, {"CenterText", 0xffffff, "Ты заработал "..money..moneySymbol}, {"EmptyLine"}, {"Button", 0x33db80, 0xffffff, "Ok"})
						else
							ecs.error("Ошибка при продаже! Дебажь!")
						end
					end

					countOfPages = showInventory(xInventory, yInventory, massivWithProfile, currentPage, currentItem) 

					break
				end
			end
		end
	end
end

local function main()
	--Кнопы
	local topButtons = {{"🏠", "Главная"}, {"⟱", "Купить"}, {"⟰", "Продать"}, {"☯", "Лотерея"},{"€", "Мой профиль"}}
	--Расстояние между кнопами
	local spaceBetweenTopButtons = 2
	--Считаем ширину
	local widthOfTopButtons = 0
	for i = 1, #topButtons do
		topButtons[i][3] = unicode.len(topButtons[i][2]) + 2
		widthOfTopButtons = widthOfTopButtons + topButtons[i][3] + spaceBetweenTopButtons
	end
	--Считаем коорду старта кноп
	local xStartOfTopButtons = math.floor(xSize / 2 - widthOfTopButtons / 2)

	--Рисуем топбар
	ecs.square(1, 1, xSize, 3, colors.topbar)

	--Рисуем белую подложку
	ecs.square(1, 4, xSize, ySize - 3, colors.background)

	--Отрисовка одной кнопки
	local function drawButton(i, x)
		local back, fore
		if i == currentMode then
			back = colors.topbarButton
			fore = colors.topbarButtonText
		else
			back = colors.topbar
			fore = colors.topbarText
		end	

		ecs.drawButton(x, 1, topButtons[i][3], 2, topButtons[i][1], back, fore)
		ecs.drawButton(x, 3, topButtons[i][3], 1, topButtons[i][2], back, fore)
	end

	--Рисуем топ кнопочки
	for i = 1, #topButtons do
		drawButton(i, xStartOfTopButtons)
		xStartOfTopButtons = xStartOfTopButtons + topButtons[i][3] + spaceBetweenTopButtons
	end

	--Запускаем нужный режим работы проги
	if currentMode == 3 then
		
		sell()
	end
end

main()

























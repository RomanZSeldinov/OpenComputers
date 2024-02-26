local fs = require("filesystem")
local unicode = require("unicode")
local gpu = require("component").gpu
local ecs = require("ECSAPI")
local image = {}

local transparentSymbol = "#"

--------------------Все, что касается сжатого формата изображений (у нас он назван "JPG")----------------------------------------------------------------------------------

--OC image format .ocif by Pirnogion
local ocif_signature1 = 0x896F6369
local ocif_signature2 = 0x00661A0A --7 bytes: 89 6F 63 69 66 1A 0A
local ocif_signature_expand = { string.char(0x89), string.char(0x6F), string.char(0x63), string.char(0x69), string.char(0x66), string.char(0x1A), string.char(0x0A) }

local BYTE = 8
local NULL_CHAR = 0

local imageAPI = {}

--Выделить бит-терминатор в первом байте utf8 символа: 1100 0010 --> 0010 0000
local function selectTerminateBit( byte )
	local x = bit32.band( bit32.bnot(byte), 0x000000FF )

	x = bit32.bor( x, bit32.rshift(x, 1) )
	x = bit32.bor( x, bit32.rshift(x, 2) )
	x = bit32.bor( x, bit32.rshift(x, 4) )
	x = bit32.bor( x, bit32.rshift(x, 8) )
	x = bit32.bor( x, bit32.rshift(x, 16) )

	return x - bit32.rshift(x, 1)
end

--Прочитать n байтов из файла, возвращает прочитанные байты как число, если не удалось прочитать, то возвращает 0
local function readBytes(file, bytes)
  local readedByte = 0
  local readedNumber = 0
  for i = bytes, 1, -1 do
    readedByte = string.byte( file:read(1) or NULL_CHAR )
    readedNumber = readedNumber + bit32.lshift(readedByte, i*8-8)
  end

  return readedNumber
end

--Преобразует цвет в hex записи в rgb запись
function HEXtoRGB(color)
  local rr = bit32.rshift( color, 16 )
  local gg = bit32.rshift( bit32.band(color, 0x00ff00), 8 )
  local bb = bit32.band(color, 0x0000ff)
 
  return rr, gg, bb
end

--Подготавливает цвета и символ для записи в файл
local function encodePixel(hexcolor_fg, hexcolor_bg, char)
	local rr_fg, gg_fg, bb_fg = HEXtoRGB( hexcolor_fg )
	local rr_bg, gg_bg, bb_bg = HEXtoRGB( hexcolor_bg )
	local ascii_char1, ascii_char2, ascii_char3, ascii_char4, ascii_char5, ascii_char6 = string.byte( char, 1, 6 )

	ascii_char1 = ascii_char1 or NULL_CHAR

	return rr_fg, gg_fg, bb_fg, rr_bg, gg_bg, bb_bg, ascii_char1, ascii_char2, ascii_char3, ascii_char4, ascii_char5, ascii_char6
end

--Декодирование utf8 символа
local function decodeChar(file)
	local first_byte = readBytes(file, 1)
	local charcode_array = {first_byte}
	local len = 1

	local middle = selectTerminateBit(first_byte)
	if ( middle == 32 ) then
		len = 2
	elseif ( middle == 16 ) then 
		len = 3
	elseif ( middle == 8 ) then
		len = 4
	elseif ( middle == 4 ) then
		len = 5
	elseif ( middle == 2 ) then
		len = 6
	end

	for i = 1, len-1 do
		table.insert( charcode_array, readBytes(file, 1) )
	end

	return string.char( table.unpack( charcode_array ) )
end

--Чтение из файла, возвращет массив изображения
local function loadJPG(path)
	local kartinka = {}
	local file = io.open(path, "rb")

	local signature1, signature2 = readBytes(file, 4), readBytes(file, 3)
	if ( signature1 ~= ocif_signature1 or signature2 ~= ocif_signature2 ) then
		file:close()
		return nil
	end

	kartinka.width = readBytes(file, 1)
	kartinka.height = readBytes(file, 1)
	kartinka.depth = readBytes(file, 1)

	for y = 1, kartinka.height, 1 do
		table.insert( kartinka, {} )
		for x = 1, kartinka.width, 1 do
			table.insert( kartinka[y], {} )
			kartinka[y][x][2] = readBytes(file, 3)
			kartinka[y][x][1] = readBytes(file, 3)
			kartinka[y][x][3] = decodeChar( file )
		end
	end

	file:close()

	return kartinka
end

--Рисование сжатого формата
function image.drawJPG(x, y, image1)
	x = x - 1
	y = y - 1

	local image2 = image.convertImageToGroupedImage(image1)

	--Перебираем массив с фонами
	for back, backValue in pairs(image2["backgrounds"]) do
		gpu.setBackground(back)
		for fore, foreValue in pairs(image2["backgrounds"][back]) do
			gpu.setForeground(fore)
			for pixel = 1, #image2["backgrounds"][back][fore] do
				if image2["backgrounds"][back][fore][pixel][3] ~= transparentSymbol then
					gpu.set(x + image2["backgrounds"][back][fore][pixel][1], y + image2["backgrounds"][back][fore][pixel][2], image2["backgrounds"][back][fore][pixel][3])
				end
			end
		end
	end
end
   
--Сохранение JPG в файл из существующего массива
function image.saveJPG(path, kartinka)
	-- Удаляем файл, если есть
	-- И делаем папку к нему
	fs.remove(path)
	fs.makeDirectory(fs.path(path))

	local file = io.open(path, "w")

	file:write( table.unpack(ocif_signature_expand) )
	file:write( string.char( kartinka.width ) )
	file:write( string.char( kartinka.height ) )
	file:write( string.char( kartinka.depth ) )

	for y = 1, kartinka.height, 1 do
		for x = 1, kartinka.width, 1 do
			local encodedPixel = { encodePixel( kartinka[y][x][2], kartinka[y][x][1], kartinka[y][x][3] ) }
			for i = 1, #encodedPixel do
				file:write( string.char( encodedPixel[i] ) )
			end
			encodedPixel = {nil, nil, nil}; encodedPixel = nil
		end
	end

	file:close()
end

---------------------------Все, что касается несжатого формата (у нас он назван "PNG")-------------------------------------------------------

-- Перевод HEX-цвета из файла (из 00ff00 делает 0x00ff00)
local function HEXtoSTRING(color,withNull)
	local stro4ka = string.format("%x",color)
	local sStro4ka = unicode.len(stro4ka)

	if sStro4ka < 6 then
		stro4ka = string.rep("0", 6 - sStro4ka) .. stro4ka
	end

	if withNull then return "0x"..stro4ka else return stro4ka end
end

--Загрузка ПНГ
local function loadPNG(path)
	local file = io.open(path, "r")
	local newPNGMassiv = {}

	local pixelCounter, lineCounter, dlinaStroki = 1, 1, nil
	for line in file:lines() do
		--Получаем длину строки
		dlinaStroki = unicode.len(line)
		--Сбрасываем счетчик пикселей
		pixelCounter = 1
		--Создаем новую строку
		newPNGMassiv[lineCounter] = {}
		--Перебираем пиксели
		for i = 1, dlinaStroki, 16 do
			--Транслируем всю хуйню в более понятную хуйню
			local back = tonumber("0x"..unicode.sub(line, i, i + 5))
			local fore = tonumber("0x"..unicode.sub(line, i + 7, i + 12))
			local symbol = unicode.sub(line, i + 14, i + 14)
			--Создаем новый пиксельс
			newPNGMassiv[lineCounter][pixelCounter] = { back, fore, symbol }
			--Увеличиваем пиксельсы
			pixelCounter = pixelCounter + 1
			--Очищаем оперативку
			back, fore, symbol = nil, nil, nil
		end

		lineCounter = lineCounter + 1
	end

	--Закрываем файл
	file:close()
	--Очищаем оперативку
	pixelCounter, lineCounter, dlinaStroki = nil, nil, nil

	return newPNGMassiv
end

-- Сохранение существующего массива ПНГ в файл
function image.savePNG(path, MasterPixels)
	-- Удаляем файл, если есть
	-- И делаем папку к нему
	fs.remove(path)
	fs.makeDirectory(fs.path(path))
	local f = io.open(path, "w")

	for j=1, #MasterPixels do
		for i=1,#MasterPixels[j] do
			f:write(HEXtoSTRING(MasterPixels[j][i][1])," ",HEXtoSTRING(MasterPixels[j][i][2])," ",MasterPixels[j][i][3]," ")
		end
		f:write("\n")
	end

	f:close()
end

--Отрисовка ПНГ
function image.drawPNG(x, y, massivSudaPihay2)
	--Уменьшаем значения кординат на 1, т.к. циклы начинаются с единицы
	x = x - 1
	y = y - 1

	--Конвертируем "сырой" формат PNG в оптимизированный и сгруппированный по цветам
	local massivSudaPihay = image.convertImageToGroupedImage(massivSudaPihay2)

	--Перебираем массив с фонами
	for back, backValue in pairs(massivSudaPihay["backgrounds"]) do
		gpu.setBackground(back)
		for fore, foreValue in pairs(massivSudaPihay["backgrounds"][back]) do
			gpu.setForeground(fore)
			for pixel = 1, #massivSudaPihay["backgrounds"][back][fore] do
				if massivSudaPihay["backgrounds"][back][fore][pixel][3] ~= transparentSymbol then
					gpu.set(x + massivSudaPihay["backgrounds"][back][fore][pixel][1], y + massivSudaPihay["backgrounds"][back][fore][pixel][2], massivSudaPihay["backgrounds"][back][fore][pixel][3])
				end
			end
		end
	end
end

---------------------Глобальные функции данного API, с ними мы и работаем---------------------------------------------------------

--Конвертируем массив классического "сырого" формата в сжатый и оптимизированный для более быстрой отрисовки
function image.convertImageToGroupedImage(PNGMassiv)
	local newPNGMassiv = { ["backgrounds"] = {} }
	--Перебираем весь массив стандартного PNG-вида по высоте
	for j = 1, #PNGMassiv do
		for i = 1, #PNGMassiv[j] do
			newPNGMassiv["backgrounds"][PNGMassiv[j][i][1]] = newPNGMassiv["backgrounds"][PNGMassiv[j][i][1]] or {}
			newPNGMassiv["backgrounds"][PNGMassiv[j][i][1]][PNGMassiv[j][i][2]] = newPNGMassiv["backgrounds"][PNGMassiv[j][i][1]][PNGMassiv[j][i][2]] or {}
			table.insert(newPNGMassiv["backgrounds"][PNGMassiv[j][i][1]][PNGMassiv[j][i][2]], {i, j, PNGMassiv[j][i][3]} )
		end
	end
	return newPNGMassiv
end

--Конвертер из PNG в JPG
function image.PNGtoJPG(PNGMassiv)
	local JPGMassiv = PNGMassiv
	local width, height = #PNGMassiv[1], #PNGMassiv

	JPGMassiv.width = width
	JPGMassiv.height = height
	JPGMassiv.depth = 8

	return JPGMassiv
end

-- Просканировать файловую систему на наличие .PNG
-- И сохранить рядом с ними аналогичную копию в формате .JPG
-- Осторожно, функция для дебага и знающих людей
-- С кривыми ручками сюда не лезь
function image.convertAllPNGtoJPG(path)
	local list = ecs.getFileList(path)
	for key, file in pairs(list) do
		if fs.isDirectory(path.."/"..file) then
			image.convertAllPNGtoJPG(path.."/"..file)
		else
			if ecs.getFileFormat(file) == ".png" or ecs.getFileFormat(file) == ".PNG" then
				print("Найден .PNG в директории \""..path.."/"..file.."\"")
				print("Загружаю этот файл...")
				PNGFile = loadPNG(path.."/"..file)
				print("Загрузка завершена!")
				print("Конвертация в JPG начата...")
				JPGFile = image.PNGtoJPG(PNGFile)
				print("Ковертация завершена!")
				print("Сохраняю .JPG в той же папке...")
				image.saveJPG(path.."/"..ecs.hideFileFormat(file)..".jpg", JPGFile)
				print("Сохранение завершено!")
				print(" ")
			end
		end
	end
end

---------------------------------------------------------------------------------------------------------------------

--Загрузка любого изображения из доступных типов
function image.load(path)
	local kartinka = {}
	local fileFormat = ecs.getFileFormat(path)
	if string.lower(fileFormat) == ".jpg" then
		kartinka["format"] = ".jpg"
		kartinka["image"] = loadJPG(path)
	elseif string.lower(fileFormat) == ".png" then
		kartinka["format"] = ".png"
		kartinka["image"] = loadPNG(path)
	else
		error("Wrong file format! (not .png or .jpg)")
	end
	return kartinka
end

--Сохранение любого формата в нужном месте
function image.save(path, kartinka)
	local fileFormat = ecs.getFileFormat(path)

	if string.lower(fileFormat) == ".jpg" then
		image.saveJPG(path, kartinka)
	elseif  string.lower(fileFormat) == ".png" then
		image.savePNG(path, kartinka)
	else
		error("Wrong file format! (not .png or .jpg)")
	end
end

--Отрисовка этого изображения
function image.draw(x, y, kartinka)
	if kartinka.format == ".jpg" then
		image.drawJPG(x, y, kartinka["image"])
	elseif kartinka.format == ".png" then
		image.drawPNG(x, y, kartinka["image"])
	end
end

function image.screenshot(path)
	--Вычисляем размер скрина
	local xSize, ySize = gpu.getResolution()

	local rawImage = {}
	for y = 1, ySize do
		rawImage[y] = {}
		for x = 1, xSize do
			local symbol, fore, back = gpu.get(x, y)
			rawImage[y][x] = { back, fore, symbol }
			symbol, fore, back = nil, nil, nil
		end
	end

	rawImage.width = #rawImage[1]
	rawImage.height = #rawImage
	rawImage.depth = 8

	image.save(path, rawImage)
end

---------------------------------------------------------------------------------------------------------------------

-- ecs.prepareToExit()
-- for i = 1, 30 do
-- 	print("Hello world bitches! " .. string.rep(tostring(math.random(100, 1000)) .. " ", 10))
-- end

-- image.draw(10, 2, image.load("System/OS/Icons/Love.png"))

-- local pathToScreen = "screenshot.jpg"

-- image.screenshot(pathToScreen)
-- ecs.prepareToExit()
-- ecs.centerText("xy", 0, "Сохранил скрин. Ща загружу фотку и нарисую его. Внимание!")
-- os.sleep(2)
-- ecs.prepareToExit()
-- image.draw(2, 2, image.load(pathToScreen))

return image














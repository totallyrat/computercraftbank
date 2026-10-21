-- Trivia, FoxyOS 18.1: the questions a CCG Casino asks in Trivia mode.
--
-- Three places a question comes from, in this order:
--   online    Open Trivia DB (opentdb.com), fetched topic by topic by the
--             CCG Server while its HTTP can reach it
--   built in  the questions below, a few for every topic, so Trivia works on
--             a world whose HTTP cannot reach the internet
--   your own  a company's questions, written in the CCG app's My Casino or
--             dropped on the table's computer as a text file (trivia.parse)
--
-- A question always has four answers, the right one first as it is kept;
-- trivia.deal shuffles them for a round and says which is right. Four, and
-- never two, because a right answer pays the same however many there are.

local trivia = {}

-- The topics, and Open Trivia DB's category for each. Minecraft is ours.
trivia.TOPICS = {
    { id = "general", name = "General", opentdb = 9 },
    { id = "science", name = "Science", opentdb = 17 },
    { id = "geography", name = "Geography", opentdb = 22 },
    { id = "history", name = "History", opentdb = 23 },
    { id = "sports", name = "Sports", opentdb = 21 },
    { id = "music", name = "Music", opentdb = 12 },
    { id = "film", name = "Film and TV", opentdb = 11 },
    { id = "games", name = "Video Games", opentdb = 15 },
    { id = "animals", name = "Animals", opentdb = 27 },
    { id = "computers", name = "Computers", opentdb = 18 },
    { id = "minecraft", name = "Minecraft" },
}
trivia.BY_ID = {}
for _, topic in ipairs(trivia.TOPICS) do trivia.BY_ID[topic.id] = topic end

trivia.MAX_TEXT = 150
trivia.MAX_ANSWER = 40
trivia.MAX_TOPIC = 16

-- Question | right answer | wrong | wrong | wrong
local BUILT_IN = {
    general = {
        "How many days are in a leap year? | 366 | 365 | 364 | 367",
        "How many sides does a hexagon have? | 6 | 5 | 7 | 8",
        "Mixing blue and yellow paint makes which colour? | Green | Purple | Orange | Brown",
        "How many hours are in a day? | 24 | 12 | 20 | 36",
        "What is the opposite of north? | South | East | West | Up",
        "How many months of the year have at least 28 days? | All 12 | 1 | 2 | 6",
        "Which shape has exactly three sides? | Triangle | Square | Circle | Pentagon",
        "How many letters are in the English alphabet? | 26 | 24 | 28 | 30",
        "Which language has the most native speakers? | Mandarin Chinese | English | Spanish | Hindi",
        "What is 12 times 12? | 144 | 124 | 132 | 156",
        "In which direction does the sun rise? | East | West | North | South",
        "What do bees make? | Honey | Silk | Butter | Jam",
    },
    science = {
        "What is the chemical formula for water? | H2O | CO2 | O2 | NaCl",
        "Which planet is known as the Red Planet? | Mars | Venus | Jupiter | Mercury",
        "Which gas do plants take in from the air? | Carbon dioxide | Oxygen | Nitrogen | Helium",
        "What is the largest planet in our solar system? | Jupiter | Saturn | Neptune | Earth",
        "At what temperature does water boil at sea level? | 100 C | 90 C | 120 C | 80 C",
        "What is the chemical symbol for gold? | Au | Ag | Go | Gd",
        "How many planets are in our solar system? | 8 | 9 | 7 | 10",
        "Which force keeps us on the ground? | Gravity | Magnetism | Friction | Inertia",
        "What is the hardest natural substance? | Diamond | Gold | Iron | Quartz",
        "Which organ pumps blood around the body? | Heart | Lungs | Liver | Kidneys",
        "What is the closest star to Earth? | The Sun | Sirius | Polaris | Alpha Centauri",
        "How many bones are in an adult human body? | 206 | 196 | 212 | 230",
    },
    geography = {
        "What is the capital of France? | Paris | Lyon | Marseille | Nice",
        "What is the capital of Japan? | Tokyo | Osaka | Kyoto | Seoul",
        "Which is the largest ocean on Earth? | Pacific | Atlantic | Indian | Arctic",
        "How many continents are there? | 7 | 5 | 6 | 8",
        "What is the longest river in Africa? | Nile | Congo | Niger | Zambezi",
        "What is the capital of Australia? | Canberra | Sydney | Melbourne | Perth",
        "Mount Everest is in which mountain range? | Himalayas | Andes | Alps | Rockies",
        "Which is the largest country by area? | Russia | Canada | China | USA",
        "What is the capital of Canada? | Ottawa | Toronto | Vancouver | Montreal",
        "Which is the largest hot desert in the world? | Sahara | Gobi | Kalahari | Arabian",
        "Most of the Amazon rainforest is in which country? | Brazil | Peru | Colombia | Venezuela",
        "What is the capital of Italy? | Rome | Milan | Venice | Naples",
    },
    history = {
        "In which year did World War II end? | 1945 | 1918 | 1939 | 1950",
        "Who was the first President of the United States? | George Washington"
            .. " | Abraham Lincoln | Thomas Jefferson | John Adams",
        "The Great Pyramid of Giza is in which country? | Egypt | Mexico | Peru | Greece",
        "In which year did people first land on the Moon? | 1969 | 1959 | 1972 | 1965",
        "Who painted the Mona Lisa? | Leonardo da Vinci | Michelangelo | Raphael | Van Gogh",
        "Which ship sank in 1912 after hitting an iceberg? | Titanic | Lusitania | Britannic"
            .. " | Bismarck",
        "In which year did the Berlin Wall fall? | 1989 | 1991 | 1979 | 1985",
        "Which empire built the Colosseum? | Roman | Greek | Ottoman | Persian",
        "Who was the first person to walk on the Moon? | Neil Armstrong | Buzz Aldrin"
            .. " | Yuri Gagarin | John Glenn",
        "In which year did Columbus first reach the Americas? | 1492 | 1592 | 1392 | 1500",
    },
    sports = {
        "How many players does a football (soccer) team have on the pitch? | 11 | 10 | 9 | 12",
        "In which sport do you hit a home run? | Baseball | Cricket | Golf | Tennis",
        "How often are the Summer Olympics held? | Every 4 years | Every 2 years | Every year"
            .. " | Every 5 years",
        "How many points is a touchdown worth in American football? | 6 | 7 | 3 | 5",
        "In tennis, what is a score of zero called? | Love | Nil | Duck | Zero",
        "How many rings are on the Olympic flag? | 5 | 4 | 6 | 7",
        "Which sport uses a shuttlecock? | Badminton | Squash | Tennis | Volleyball",
        "How many holes are in a standard round of golf? | 18 | 9 | 12 | 21",
    },
    music = {
        "How many strings does a standard guitar have? | 6 | 4 | 5 | 7",
        "How many keys does a standard piano have? | 88 | 76 | 92 | 64",
        "Which of these has black and white keys? | Piano | Violin | Trumpet | Drum",
        "Which band sang Hey Jude? | The Beatles | The Rolling Stones | Queen | ABBA",
        "Who is known as the King of Pop? | Michael Jackson | Elvis Presley | Prince"
            .. " | Justin Bieber",
        "How many lines are on a musical staff? | 5 | 4 | 6 | 7",
        "Which composer kept writing music after going deaf? | Beethoven | Mozart | Bach"
            .. " | Chopin",
        "What is a group of four musicians called? | Quartet | Trio | Quintet | Duet",
    },
    film = {
        "What colour is Shrek? | Green | Blue | Brown | Grey",
        "In The Lion King, what is Simba's father called? | Mufasa | Scar | Rafiki | Timon",
        "Which school of magic does Harry Potter go to? | Hogwarts | Durmstrang | Beauxbatons"
            .. " | Ilvermorny",
        "What kind of fish is Nemo? | Clownfish | Goldfish | Angelfish | Tuna",
        "Who lives in a pineapple under the sea? | SpongeBob | Patrick | Squidward | Mr. Krabs",
        "In Star Wars, what is Darth Vader's real name? | Anakin Skywalker | Luke Skywalker"
            .. " | Obi-Wan Kenobi | Han Solo",
        "Which toy cowboy is the hero of Toy Story? | Woody | Buzz | Jessie | Rex",
        "In Frozen, what is the snowman called? | Olaf | Sven | Kristoff | Hans",
    },
    games = {
        "Which famous plumber wears a red cap? | Mario | Luigi | Wario | Toad",
        "What type of Pokemon is Pikachu? | Electric | Fire | Water | Grass",
        "What are the falling pieces in Tetris called? | Tetrominoes | Polygons | Cubes | Bricks",
        "Which company makes the PlayStation? | Sony | Microsoft | Nintendo | Sega",
        "Who is the hero of The Legend of Zelda? | Link | Zelda | Ganon | Epona",
        "What colour is Sonic the Hedgehog? | Blue | Red | Green | Yellow",
        "Which company makes the Xbox? | Microsoft | Sony | Nintendo | Valve",
        "What does Pac-Man eat to chase the ghosts? | Power pellets | Cherries | Stars"
            .. " | Mushrooms",
    },
    animals = {
        "How many legs does a spider have? | 8 | 6 | 10 | 12",
        "What is the largest animal on Earth? | Blue whale | Elephant | Giraffe"
            .. " | Great white shark",
        "What is a baby kangaroo called? | Joey | Kit | Cub | Calf",
        "Which bird is famous for copying human speech? | Parrot | Pigeon | Owl | Penguin",
        "What do caterpillars turn into? | Butterflies | Beetles | Bees | Spiders",
        "What is the fastest land animal? | Cheetah | Lion | Horse | Gazelle",
        "How many hearts does an octopus have? | 3 | 1 | 2 | 4",
        "Which animal is called the King of the Jungle? | Lion | Tiger | Gorilla | Elephant",
        "What do pandas mostly eat? | Bamboo | Fish | Berries | Grass",
        "Which mammal can truly fly? | Bat | Flying squirrel | Sugar glider | Colugo",
    },
    computers = {
        "What does CPU stand for? | Central Processing Unit | Computer Power Unit"
            .. " | Central Program Utility | Core Processing Unit",
        "How many bits are in a byte? | 8 | 4 | 16 | 10",
        "What does WWW stand for? | World Wide Web | Wide World Web | World Web Wire"
            .. " | Web World Wide",
        "Which language are ComputerCraft programs written in? | Lua | Python | Java"
            .. " | JavaScript",
        "What does RAM stand for? | Random Access Memory | Read Access Memory"
            .. " | Rapid Action Memory | Run All Memory",
        "Which keys copy on most computers? | Ctrl+C | Ctrl+V | Ctrl+X | Ctrl+Z",
    },
    minecraft = {
        "What do you give a wolf to tame it? | Bones | Fish | Wheat | Carrots",
        "Which mob hisses and explodes? | Creeper | Zombie | Skeleton | Spider",
        "Which block is a Nether portal's frame made of? | Obsidian | Cobblestone | Netherrack"
            .. " | Glass",
        "What do you feed cows to breed them? | Wheat | Carrots | Seeds | Apples",
        "Which is the strongest tool material? | Netherite | Diamond | Iron | Gold",
        "How much obsidian does the smallest portal frame need, without corners? | 10 | 14"
            .. " | 12 | 8",
        "What does an Enderman drop? | Ender pearl | Eye of ender | Blaze rod | Ghast tear",
        "Where does the Ender Dragon live? | The End | The Nether | The Overworld | The Void",
        "Which of these goes into a cake? | Milk | Coal | String | Flint",
        "What is the weakest pickaxe that can mine diamond ore? | Iron | Stone | Gold | Wood",
        "What do villagers trade with? | Emeralds | Diamonds | Gold | Iron",
        "What do you get when you smelt sand? | Glass | Sandstone | Clay | Bricks",
        "How many slots does a single chest have? | 27 | 36 | 18 | 54",
        "Which of these mobs drops gunpowder? | Creeper | Skeleton | Zombie | Slime",
    },
}

-- Text a ComputerCraft screen can show: printable ASCII, the commonest
-- accents spelled without them, one line, trimmed, at most `most` long.
local PLAIN = { ["\195\161"] = "a", ["\195\160"] = "a", ["\195\162"] = "a", ["\195\164"] = "a",
    ["\195\169"] = "e", ["\195\168"] = "e", ["\195\170"] = "e", ["\195\171"] = "e",
    ["\195\173"] = "i", ["\195\175"] = "i", ["\195\179"] = "o", ["\195\182"] = "o",
    ["\195\180"] = "o", ["\195\186"] = "u", ["\195\188"] = "u", ["\195\177"] = "n",
    ["\195\167"] = "c", ["\195\137"] = "E", ["\195\159"] = "ss",
    ["\226\128\152"] = "'", ["\226\128\153"] = "'", ["\226\128\156"] = '"',
    ["\226\128\157"] = '"', ["\226\128\147"] = "-", ["\226\128\148"] = "-",
    ["\226\128\166"] = "..." }
function trivia.clean(text, most)
    text = tostring(text or "")
    for from, to in pairs(PLAIN) do text = text:gsub(from, to) end
    text = text:gsub("[\r\n\t]", " "):gsub("[^\32-\126]", ""):gsub("%s+", " ")
    text = text:match("^%s*(.-)%s*$")
    if most and #text > most then return nil end
    return text
end

-- One question from its parts: `answers` has the right one first. Nil and
-- why, for anything a screen could not show or a round could not use.
function trivia.make(topic, text, answers)
    local question = trivia.clean(text, trivia.MAX_TEXT)
    if not question or #question < 5 then return nil, "The question is missing or too long" end
    if type(answers) ~= "table" or #answers ~= 4 then return nil, "It needs four answers" end
    local choices, seen = {}, {}
    for index = 1, 4 do
        local answer = trivia.clean(answers[index], trivia.MAX_ANSWER)
        if not answer or answer == "" then return nil, "An answer is missing or too long" end
        if seen[answer:lower()] then return nil, "Two answers are the same" end
        seen[answer:lower()] = true
        choices[index] = answer
    end
    local label = trivia.clean(topic, trivia.MAX_TOPIC)
    if not label or label == "" then label = "Our questions" end
    return { topic = label, text = question, choices = choices }
end

-- Every built-in question, made once: { id, topic, topic_name, text, choices }.
function trivia.builtIn()
    if trivia.cache then return trivia.cache end
    local all, byTopic = {}, {}
    for _, topic in ipairs(trivia.TOPICS) do
        byTopic[topic.id] = {}
        for index, line in ipairs(BUILT_IN[topic.id] or {}) do
            local parts = {}
            for part in (line .. "|"):gmatch("([^|]*)|") do parts[#parts + 1] = part end
            local made = trivia.make(topic.name, parts[1], { parts[2], parts[3], parts[4], parts[5] })
            if made then
                made.id, made.topic_id, made.source = topic.id .. index, topic.id, "built-in"
                all[#all + 1] = made
                byTopic[topic.id][#byTopic[topic.id] + 1] = made
            end
        end
    end
    trivia.cache = { all = all, byTopic = byTopic }
    return trivia.cache
end

-- Your own, from a text file:
--
--   # Minecraft
--   What do you give a wolf to tame it? | Bones | Fish | Wheat | Carrots
--
-- A line starting with # names the topic for the questions under it. Every
-- other line that is not empty is a question, then its four answers with
-- the right one first, split by |. Returns the questions, and the lines that
-- were not, with why.
function trivia.parse(text)
    local questions, problems, topic = {}, {}, "Our questions"
    local number = 0
    for line in (tostring(text or "") .. "\n"):gmatch("([^\n]*)\n") do
        number = number + 1
        line = line:gsub("\r", "")
        local heading = line:match("^%s*#%s*(.-)%s*$")
        if heading then
            topic = trivia.clean(heading, trivia.MAX_TOPIC) or topic
        elseif line:match("%S") then
            local parts = {}
            for part in (line .. "|"):gmatch("([^|]*)|") do parts[#parts + 1] = part end
            local made, why
            if #parts ~= 5 then
                why = "needs a question and four answers, split by |"
            else
                made, why = trivia.make(topic, parts[1], { parts[2], parts[3], parts[4], parts[5] })
            end
            if made then
                questions[#questions + 1] = made
            else
                problems[#problems + 1] = "Line " .. number .. ": " .. tostring(why)
            end
        end
    end
    return questions, problems
end

-- Open Trivia DB asked for encode=url3986: every field percent-encoded.
function trivia.urlDecode(text)
    return (tostring(text or ""):gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end))
end

-- One of Open Trivia DB's results as one of ours, or nil if it will not do.
function trivia.fromOpenTdb(result, topicId)
    if type(result) ~= "table" or result.type ~= "multiple"
        or type(result.incorrect_answers) ~= "table" or #result.incorrect_answers ~= 3 then
        return nil
    end
    local topic = trivia.BY_ID[topicId]
    local wrong = result.incorrect_answers
    local made = trivia.make(topic and topic.name or "Trivia", trivia.urlDecode(result.question),
        { trivia.urlDecode(result.correct_answer), trivia.urlDecode(wrong[1]),
            trivia.urlDecode(wrong[2]), trivia.urlDecode(wrong[3]) })
    if not made then return nil end
    made.topic_id, made.source = topicId, "online"
    made.id = "W:" .. made.text:sub(1, 60)
    return made
end

-- A question as a round asks it: the answers shuffled, and which is right.
function trivia.deal(question, random)
    random = random or math.random
    local order = { 1, 2, 3, 4 }
    for index = 4, 2, -1 do
        local other = random(1, index)
        order[index], order[other] = order[other], order[index]
    end
    local choices, answer = {}, nil
    for index, from in ipairs(order) do
        choices[index] = question.choices[from]
        if from == 1 then answer = index end
    end
    return { id = question.id, topic = question.topic, topic_id = question.topic_id,
        source = question.source, text = question.text, choices = choices, answer = answer }
end

return trivia

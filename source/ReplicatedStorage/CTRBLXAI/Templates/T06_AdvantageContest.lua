local Template = {}

Template.Id = "T06"
Template.Name = "Advantage Contest"
Template.Width = 30
Template.Height = 20

Template.Grid = {
	{ "PD", "PD", "PD", "PD", "PD", "PD", "PD", "PD", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "PD", "PD", "PD", "PD", "PD", "PD", "PD", "PD", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "PD", "PD", "PD", "PD", "PD", "PD", "PD", "PD", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "POI", "POI", "POI", "POI", "POI", "NEU", "NEU", "NEU", "NEU" },
	{ "PD", "PD", "PD", "PD", "PD", "PD", "PD", "PD", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "POI", "POI", "POI", "POI", "POI", "NEU", "NEU", "NEU", "NEU" },
	{ "PD", "PD", "PD", "PD", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "POI", "POI", "POI", "POI", "POI", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "ADV", "ADV", "ADV", "ADV", "ADV", "ADV", "ADV", "ADV", "ADV", "LAN", "POI", "POI", "POI", "POI", "POI", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "ADV", "ADV", "ADV", "ADV", "ADV", "ADV", "ADV", "ADV", "ADV", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "LAN", "LAN", "LAN", "BLK", "BLK", "BLK", "BLK", "BLK", "BLK", "BLK", "BLK", "BLK", "BLK", "BLK", "BLK", "BLK", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "LAN", "LAN", "LAN", "BLK", "BLK", "BLK", "BLK", "BLK", "BLK", "BLK", "BLK", "BLK", "BLK", "BLK", "BLK", "BLK", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "LAN", "LAN", "LAN", "BLK", "BLK", "BLK", "BLK", "HZD", "HZD", "HZD", "HZD", "HZD", "BLK", "BLK", "BLK", "BLK", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "LAN", "LAN", "LAN", "BLK", "BLK", "BLK", "BLK", "HZD", "HZD", "HZD", "HZD", "HZD", "BLK", "BLK", "BLK", "BLK", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "LAN", "LAN", "LAN", "BLK", "BLK", "BLK", "BLK", "HZD", "HZD", "HZD", "HZD", "HZD", "BLK", "BLK", "BLK", "BLK", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "LAN", "LAN", "LAN", "BLK", "BLK", "BLK", "BLK", "BLK", "BLK", "BLK", "BLK", "BLK", "BLK", "BLK", "BLK", "BLK", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "ADV", "ADV", "ADV", "ADV", "ADV", "ADV", "ADV", "ADV", "ADV", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "POI", "POI", "POI", "POI", "POI", "LAN", "LAN", "ADV", "ADV", "ADV", "ADV", "ADV", "ADV", "ADV", "ADV", "ADV", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "POI", "POI", "POI", "POI", "POI", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "ED", "ED", "ED", "ED" },
	{ "NEU", "NEU", "NEU", "NEU", "POI", "POI", "POI", "POI", "POI", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "ED" },
	{ "NEU", "NEU", "NEU", "NEU", "POI", "POI", "POI", "POI", "POI", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "ED" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "ED" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "ED" },
}

return Template

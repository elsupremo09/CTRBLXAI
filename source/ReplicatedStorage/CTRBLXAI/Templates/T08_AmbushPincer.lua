local Template = {}

Template.Id = "T08"
Template.Name = "Ambush Pincer"
Template.Width = 29
Template.Height = 18

Template.Grid = {
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "ADV", "ADV", "ADV", "ADV", "ADV", "NEU", "NEU", "LAN", "LAN", "LAN", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "ADV", "ADV", "ADV", "ADV", "ADV", "LAN", "LAN", "LAN", "HZD", "HZD", "HZD", "HZD", "HZD", "ED", "ED", "ED", "ED", "ED", "ED", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "ADV", "ADV", "ADV", "ADV", "ADV", "LAN", "LAN", "LAN", "HZD", "HZD", "HZD", "HZD", "HZD", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "PD", "PD", "PD", "PD", "PD", "LAN", "LAN", "ADV", "ADV", "ADV", "ADV", "ADV", "LAN", "BLK", "BLK", "HZD", "HZD", "HZD", "HZD", "HZD", "BLK", "LAN", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "PD", "PD", "PD", "PD", "PD", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "BLK", "BLK", "HZD", "HZD", "HZD", "ADV", "ADV", "BLK", "LAN", "POI", "POI", "POI", "POI", "POI" },
	{ "NEU", "NEU", "PD", "PD", "PD", "PD", "PD", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "BLK", "BLK", "HZD", "HZD", "HZD", "ADV", "ADV", "BLK", "LAN", "POI", "POI", "POI", "POI", "POI" },
	{ "NEU", "NEU", "PD", "PD", "PD", "PD", "PD", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "BLK", "BLK", "HZD", "HZD", "HZD", "ADV", "ADV", "BLK", "LAN", "POI", "POI", "POI", "POI", "POI" },
	{ "NEU", "NEU", "PD", "PD", "PD", "PD", "PD", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "BLK", "BLK", "HZD", "HZD", "HZD", "ADV", "ADV", "BLK", "LAN", "POI", "POI", "POI", "POI", "POI" },
	{ "NEU", "NEU", "PD", "PD", "PD", "PD", "PD", "LAN", "LAN", "ADV", "ADV", "ADV", "ADV", "ADV", "LAN", "BLK", "BLK", "HZD", "HZD", "HZD", "HZD", "HZD", "BLK", "LAN", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "ADV", "ADV", "ADV", "ADV", "ADV", "LAN", "LAN", "LAN", "HZD", "HZD", "HZD", "HZD", "HZD", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "ADV", "ADV", "ADV", "ADV", "ADV", "LAN", "LAN", "LAN", "HZD", "HZD", "HZD", "HZD", "HZD", "ED", "ED", "ED", "ED", "ED", "ED", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "ADV", "ADV", "ADV", "ADV", "ADV", "NEU", "NEU", "LAN", "LAN", "LAN", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "NEU" },
}

return Template

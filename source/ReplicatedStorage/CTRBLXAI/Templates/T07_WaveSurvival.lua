local Template = {}

Template.Id = "T07"
Template.Name = "Wave Survival"
Template.Width = 30
Template.Height = 30

Template.Grid = {
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "POI", "POI", "POI", "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "POI", "POI", "POI", "LAN", "NEU", "NEU", "LAN", "LAN", "OBS", "OBS", "LAN", "LAN", "LAN", "NEU", "NEU", "ADV", "ADV", "ADV", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "POI", "POI", "POI", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU", "ADV", "ADV", "ADV", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "ADV", "ADV", "ADV", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "HZD", "HZD", "HZD", "HZD", "HZD", "HZD", "HZD", "HZD", "HZD", "HZD", "HZD", "HZD", "LAN", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "HZD", "OBS", "OBS", "OBS", "HZD", "HZD", "HZD", "HZD", "OBS", "OBS", "OBS", "HZD", "LAN", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "ED", "ED", "ED", "ED", "NEU", "NEU", "LAN", "LAN", "LAN", "HZD", "HZD", "HZD", "HZD", "HZD", "HZD", "ADV", "ADV", "HZD", "HZD", "HZD", "HZD", "LAN", "LAN", "NEU", "NEU", "NEU", "ED", "ED", "ED", "ED" },
	{ "ED", "ED", "ED", "ED", "NEU", "LAN", "LAN", "LAN", "LAN", "HZD", "HZD", "HZD", "PD", "PD", "PD", "PD", "PD", "PD", "ADV", "HZD", "HZD", "LAN", "LAN", "LAN", "NEU", "NEU", "ED", "ED", "ED", "ED" },
	{ "ED", "ED", "ED", "ED", "LAN", "LAN", "OBS", "LAN", "LAN", "HZD", "OBS", "HZD", "PD", "PD", "PD", "PD", "PD", "PD", "ADV", "HZD", "HZD", "LAN", "LAN", "LAN", "LAN", "NEU", "ED", "ED", "ED", "ED" },
	{ "ED", "ED", "ED", "ED", "LAN", "LAN", "OBS", "LAN", "LAN", "HZD", "OBS", "ADV", "PD", "PD", "PD", "PD", "PD", "PD", "ADV", "OBS", "HZD", "LAN", "LAN", "OBS", "LAN", "LAN", "ED", "ED", "ED", "ED" },
	{ "ED", "ED", "ED", "ED", "LAN", "LAN", "LAN", "LAN", "LAN", "HZD", "OBS", "ADV", "PD", "PD", "PD", "PD", "PD", "PD", "HZD", "OBS", "HZD", "LAN", "LAN", "OBS", "LAN", "LAN", "ED", "ED", "ED", "ED" },
	{ "ED", "ED", "ED", "ED", "NEU", "LAN", "LAN", "LAN", "LAN", "HZD", "HZD", "ADV", "PD", "PD", "PD", "PD", "PD", "PD", "HZD", "OBS", "HZD", "LAN", "LAN", "LAN", "LAN", "NEU", "ED", "ED", "ED", "ED" },
	{ "ED", "ED", "ED", "ED", "NEU", "NEU", "LAN", "LAN", "LAN", "HZD", "HZD", "HZD", "PD", "PD", "PD", "PD", "PD", "PD", "HZD", "HZD", "HZD", "LAN", "LAN", "LAN", "NEU", "NEU", "ED", "ED", "ED", "ED" },
	{ "ED", "ED", "ED", "ED", "NEU", "NEU", "NEU", "LAN", "LAN", "HZD", "HZD", "HZD", "HZD", "ADV", "ADV", "HZD", "HZD", "HZD", "HZD", "HZD", "HZD", "LAN", "LAN", "NEU", "NEU", "NEU", "ED", "ED", "ED", "ED" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "LAN", "HZD", "OBS", "OBS", "OBS", "HZD", "HZD", "HZD", "HZD", "OBS", "OBS", "OBS", "HZD", "LAN", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "ADV", "ADV", "ADV", "HZD", "HZD", "HZD", "HZD", "HZD", "HZD", "HZD", "HZD", "HZD", "HZD", "HZD", "HZD", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "ADV", "ADV", "ADV", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "ADV", "ADV", "ADV", "NEU", "NEU", "LAN", "LAN", "LAN", "OBS", "OBS", "LAN", "LAN", "LAN", "NEU", "LAN", "LAN", "POI", "POI", "POI", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "LAN", "POI", "POI", "POI", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU", "NEU", "POI", "POI", "POI", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
}

return Template

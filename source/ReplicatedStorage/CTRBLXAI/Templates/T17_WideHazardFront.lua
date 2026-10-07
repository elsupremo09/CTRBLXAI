local Template = {}

Template.Id = "T17"
Template.Name = "Wide Hazard Front"
Template.Width = 30
Template.Height = 20

Template.Grid = {
	{ "ED", "ED", "ED", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "ED", "ED" },
	{ "ED", "ED", "ED", "OBS", "OBS", "HZD", "HZD", "HZD", "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "LAN", "SLW", "SLW", "NEU", "LAN", "ED", "ED" },
	{ "ED", "ED", "ED", "OBS", "OBS", "HZD", "HZD", "HZD", "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "NEU", "SLW", "SLW", "SLW", "LAN", "ED", "ED" },
	{ "NEU", "OBS", "OBS", "OBS", "OBS", "HZD", "HZD", "HZD", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU", "SLW", "SLW", "ADV", "ADV", "LAN", "LAN", "ADV", "ADV", "SLW", "SLW", "LAN", "LAN", "LAN" },
	{ "NEU", "OBS", "OBS", "OBS", "OBS", "NEU", "ADV", "ADV", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU", "SLW", "SLW", "ADV", "ADV", "LAN", "LAN", "ADV", "ADV", "SLW", "SLW", "NEU", "LAN", "LAN" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "ADV", "ADV", "PD", "PD", "ADV", "ADV", "LAN", "LAN", "LAN", "LAN", "HZD", "SLW", "SLW", "ADV", "ADV", "PD", "PD", "ADV", "ADV", "NEU", "NEU", "NEU", "LAN", "LAN" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "PD", "PD", "ADV", "ADV", "OBS", "LAN", "LAN", "LAN", "HZD", "HZD", "OBS", "OBS", "OBS", "PD", "PD", "HZD", "HZD", "NEU", "SLW", "SLW", "LAN", "LAN" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "ADV", "ADV", "OBS", "LAN", "LAN", "LAN", "HZD", "HZD", "OBS", "OBS", "OBS", "PD", "PD", "HZD", "HZD", "NEU", "SLW", "SLW", "LAN", "LAN" },
	{ "NEU", "NEU", "SLW", "SLW", "NEU", "NEU", "NEU", "NEU", "NEU", "SLW", "SLW", "SLW", "OBS", "ED", "ED", "ED", "ED", "SLW", "OBS", "OBS", "OBS", "LAN", "LAN", "HZD", "HZD", "NEU", "SLW", "SLW", "POI", "POI" },
	{ "POI", "POI", "SLW", "SLW", "NEU", "NEU", "NEU", "NEU", "NEU", "SLW", "SLW", "SLW", "OBS", "ED", "ED", "ED", "ED", "SLW", "HZD", "HZD", "ADV", "ADV", "LAN", "NEU", "NEU", "NEU", "SLW", "SLW", "POI", "POI" },
	{ "POI", "POI", "SLW", "SLW", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "HZD", "HZD", "ED", "ED", "ED", "ED", "SLW", "HZD", "HZD", "ADV", "ADV", "LAN", "NEU", "NEU", "NEU", "SLW", "SLW", "POI", "POI" },
	{ "POI", "POI", "SLW", "SLW", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "OBS", "OBS", "HZD", "ED", "ED", "ED", "ED", "OBS", "OBS", "NEU", "NEU", "LAN", "LAN", "HZD", "HZD", "NEU", "SLW", "SLW", "NEU", "NEU" },
	{ "NEU", "NEU", "SLW", "SLW", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "OBS", "OBS", "HZD", "ED", "ED", "ED", "ED", "OBS", "OBS", "ADV", "ADV", "LAN", "LAN", "HZD", "HZD", "HZD", "SLW", "SLW", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "OBS", "OBS", "SLW", "SLW", "NEU", "PD", "PD", "OBS", "OBS", "HZD", "HZD", "NEU", "LAN", "LAN", "OBS", "OBS", "ADV", "ADV", "PD", "PD", "HZD", "HZD", "HZD", "SLW", "SLW", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "OBS", "OBS", "SLW", "ADV", "ADV", "PD", "PD", "OBS", "OBS", "HZD", "HZD", "NEU", "LAN", "LAN", "NEU", "NEU", "ADV", "ADV", "PD", "PD", "ADV", "ADV", "HZD", "HZD", "NEU", "NEU", "NEU" },
	{ "NEU", "HZD", "HZD", "OBS", "OBS", "SLW", "ADV", "ADV", "PD", "PD", "LAN", "LAN", "NEU", "NEU", "NEU", "LAN", "LAN", "NEU", "NEU", "NEU", "LAN", "LAN", "LAN", "ADV", "ADV", "SLW", "SLW", "NEU", "NEU", "NEU" },
	{ "NEU", "HZD", "HZD", "OBS", "OBS", "SLW", "ADV", "ADV", "SLW", "SLW", "LAN", "LAN", "NEU", "NEU", "NEU", "LAN", "LAN", "NEU", "NEU", "NEU", "LAN", "HZD", "HZD", "ADV", "ADV", "SLW", "SLW", "NEU", "NEU", "NEU" },
	{ "ED", "ED", "HZD", "OBS", "OBS", "SLW", "SLW", "SLW", "SLW", "SLW", "LAN", "LAN", "NEU", "NEU", "NEU", "LAN", "LAN", "NEU", "NEU", "NEU", "LAN", "HZD", "HZD", "SLW", "SLW", "SLW", "SLW", "NEU", "ED", "ED" },
	{ "ED", "ED", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "ED", "ED" },
	{ "ED", "ED", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "ED", "ED" },
}

return Template

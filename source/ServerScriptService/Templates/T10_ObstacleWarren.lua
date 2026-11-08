local Template = {}

Template.Id = "T10"
Template.Name = "Obstacle Warren"
Template.Width = 25
Template.Height = 20

Template.Grid = {
	{ "ED", "ED", "ED", "ED", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "ED", "ED", "ED", "ED", "NEU", "NEU", "NEU", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "ED", "ED", "ED", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "ED", "ED", "ED", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "HZD", "HZD", "HZD", "HZD", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "OBS", "OBS", "OBS", "OBS", "OBS", "OBS", "OBS", "OBS", "OBS", "OBS", "HZD", "HZD", "HZD", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "OBS", "OBS", "OBS", "OBS", "OBS", "OBS", "OBS", "OBS", "OBS", "OBS", "HZD", "HZD", "HZD", "LAN", "LAN", "OBS", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "OBS", "OBS", "OBS", "OBS", "OBS", "OBS", "OBS", "OBS", "OBS", "OBS", "SLW", "SLW", "HZD", "LAN", "LAN", "OBS", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "PD", "PD", "PD", "ADV", "ADV", "SLW", "SLW", "HZD", "LAN", "LAN", "OBS", "OBS", "OBS", "LAN", "LAN", "LAN", "POI", "POI", "POI", "POI" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "PD", "PD", "PD", "ADV", "ADV", "SLW", "SLW", "HZD", "LAN", "LAN", "OBS", "OBS", "OBS", "ED", "ED", "ED", "POI", "POI", "POI", "POI" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "PD", "PD", "PD", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "OBS", "OBS", "OBS", "ED", "ED", "ED", "POI", "POI", "POI", "POI" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "PD", "PD", "PD", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "OBS", "OBS", "OBS", "ED", "ED", "ED", "POI", "POI", "POI", "POI" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "PD", "PD", "PD", "ADV", "ADV", "SLW", "SLW", "HZD", "LAN", "LAN", "OBS", "OBS", "OBS", "ED", "ED", "ED", "POI", "POI", "POI", "POI" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "PD", "PD", "PD", "ADV", "ADV", "SLW", "SLW", "HZD", "LAN", "LAN", "OBS", "OBS", "OBS", "LAN", "LAN", "LAN", "POI", "POI", "POI", "POI" },
	{ "OBS", "OBS", "OBS", "OBS", "OBS", "OBS", "OBS", "OBS", "OBS", "OBS", "SLW", "SLW", "HZD", "LAN", "LAN", "OBS", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU" },
	{ "OBS", "OBS", "OBS", "OBS", "OBS", "OBS", "OBS", "OBS", "OBS", "OBS", "HZD", "HZD", "HZD", "LAN", "LAN", "OBS", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "OBS", "OBS", "OBS", "OBS", "OBS", "OBS", "OBS", "OBS", "OBS", "OBS", "HZD", "HZD", "HZD", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "ED", "ED", "ED", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "HZD", "HZD", "HZD", "HZD", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "ED", "ED", "ED", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "ED", "ED", "ED", "ED", "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "ED", "ED", "ED", "ED", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
}

return Template

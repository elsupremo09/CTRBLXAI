local Template = {}

Template.Id = "T09"
Template.Name = "Hazard Gauntlet"
Template.Width = 31
Template.Height = 18

Template.Grid = {
	{ "NEU", "NEU", "NEU", "ED", "ED", "ED", "ED", "NEU", "OBS", "OBS", "NEU", "ED", "ED", "ED", "ED", "OBS", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "ED", "ED", "ED", "ED", "NEU", "OBS", "OBS", "NEU", "ED", "ED", "ED", "ED", "OBS", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "ED", "ED", "ED", "ED", "NEU", "OBS", "OBS", "NEU", "ED", "ED", "ED", "ED", "OBS", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "LAN", "LAN", "LAN", "LAN", "LAN", "OBS", "OBS", "LAN", "LAN", "LAN", "LAN", "LAN", "OBS", "LAN", "SLW", "SLW", "SLW", "SLW", "SLW", "SLW", "SLW", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "LAN", "LAN", "LAN", "LAN", "LAN", "OBS", "OBS", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "SLW", "SLW", "SLW", "SLW", "SLW", "SLW", "SLW", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "LAN", "LAN", "NEU", "NEU", "LAN", "OBS", "OBS", "LAN", "NEU", "NEU", "NEU", "LAN", "LAN", "LAN", "SLW", "SLW", "HZD", "HZD", "HZD", "HZD", "HZD", "NEU", "NEU", "LAN", "LAN", "LAN", "OBS", "OBS" },
	{ "NEU", "NEU", "NEU", "LAN", "LAN", "NEU", "NEU", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "SLW", "SLW", "HZD", "HZD", "HZD", "HZD", "HZD", "NEU", "NEU", "LAN", "LAN", "PD", "PD", "PD" },
	{ "ED", "ED", "ED", "LAN", "LAN", "OBS", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "HZD", "HZD", "HZD", "HZD", "NEU", "SLW", "SLW", "HZD", "HZD", "ADV", "ADV", "ADV", "NEU", "NEU", "LAN", "LAN", "PD", "PD", "PD" },
	{ "ED", "ED", "ED", "LAN", "LAN", "OBS", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "HZD", "HZD", "HZD", "HZD", "OBS", "SLW", "SLW", "HZD", "HZD", "ADV", "OBJ", "OBJ", "LAN", "LAN", "LAN", "LAN", "PD", "PD", "PD" },
	{ "ED", "ED", "ED", "LAN", "LAN", "OBS", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "HZD", "HZD", "HZD", "HZD", "OBS", "SLW", "SLW", "HZD", "HZD", "ADV", "OBJ", "OBJ", "LAN", "LAN", "LAN", "LAN", "PD", "PD", "PD" },
	{ "ED", "ED", "ED", "LAN", "LAN", "OBS", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "HZD", "HZD", "HZD", "HZD", "NEU", "SLW", "SLW", "HZD", "HZD", "ADV", "ADV", "ADV", "NEU", "NEU", "LAN", "LAN", "PD", "PD", "PD" },
	{ "NEU", "NEU", "NEU", "LAN", "LAN", "NEU", "NEU", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "SLW", "SLW", "HZD", "HZD", "HZD", "HZD", "HZD", "NEU", "NEU", "LAN", "LAN", "PD", "PD", "PD" },
	{ "NEU", "NEU", "NEU", "LAN", "LAN", "NEU", "NEU", "LAN", "OBS", "OBS", "LAN", "NEU", "NEU", "NEU", "LAN", "LAN", "LAN", "SLW", "SLW", "HZD", "HZD", "HZD", "HZD", "HZD", "NEU", "NEU", "LAN", "LAN", "LAN", "OBS", "OBS" },
	{ "NEU", "NEU", "NEU", "LAN", "LAN", "LAN", "LAN", "LAN", "OBS", "OBS", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "SLW", "SLW", "SLW", "SLW", "SLW", "SLW", "SLW", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "LAN", "LAN", "LAN", "LAN", "LAN", "OBS", "OBS", "LAN", "LAN", "LAN", "LAN", "LAN", "OBS", "LAN", "SLW", "SLW", "SLW", "SLW", "SLW", "SLW", "SLW", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "ED", "ED", "ED", "ED", "NEU", "OBS", "OBS", "NEU", "ED", "ED", "ED", "ED", "OBS", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "ED", "ED", "ED", "ED", "NEU", "OBS", "OBS", "NEU", "ED", "ED", "ED", "ED", "OBS", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "ED", "ED", "ED", "ED", "NEU", "OBS", "OBS", "NEU", "ED", "ED", "ED", "ED", "OBS", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
}

return Template

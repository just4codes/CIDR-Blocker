#pragma semicolon 1

#define DEBUG

#define PLUGIN_AUTHOR "Fishy"
#define PLUGIN_VERSION "0.0.1"

#include <sourcemod>
#include <sdktools>

#pragma newdecls required

Database hDB;

char Cache[512][4][255]; //0:CIDR, 1:START, 2:END, 3:KICK_MESSAGE
char Whitelist[512][2][32]; //0:Type (steam, ip), 1:Identity

int CacheRowCount;
int WhitelistRowCount;

bool CacheLoaded;
bool WhitelistLoaded;

public Plugin myinfo = 
{
	name = "CIDR Blocker",
	author = PLUGIN_AUTHOR,
	description = "Blocks CIDR (Classless Inter-Domain Routing) IP Ranges",
	version = PLUGIN_VERSION,
	url = "https://keybase.io/rumblefrog"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	hDB = SQL_Connect("cidr_blocker", true, error, err_max);
	
	if (hDB == INVALID_HANDLE)
		return APLRes_Failure;
	
	char ListCreateSQL[] = "CREATE TABLE IF NOT EXISTS `cidr_list` ( `id` INT NOT NULL AUTO_INCREMENT , `cidr` VARCHAR(32) NOT NULL , `kick_message` VARCHAR(255) NOT NULL , `comment` VARCHAR(255) NULL , PRIMARY KEY (`id`)) ENGINE = InnoDB CHARSET=utf8mb4 COLLATE utf8mb4_general_ci;";
	char WhitelistCreateSQL[] = "CREATE TABLE IF NOT EXISTS `cidr_whitelist` ( `id` INT NOT NULL AUTO_INCREMENT , `type` ENUM('steam','ip') NOT NULL , `identity` VARCHAR(255) NOT NULL , `comment` VARCHAR(255) NULL , PRIMARY KEY (`id`)) ENGINE = InnoDB CHARSET=utf8mb4 COLLATE utf8mb4_general_ci;";
	char LogCreateSQL[] = "CREATE TABLE IF NOT EXISTS `cidr_log` ( `id` INT NOT NULL AUTO_INCREMENT , `ip` VARBINARY(16) NOT NULL , `steamid` VARCHAR(32) NOT NULL , `name` VARCHAR(255) NOT NULL , `cidr` VARCHAR(32) NOT NULL , `time` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP , PRIMARY KEY (`id`), INDEX (`steamid`), INDEX (`ip`), INDEX (`cidr`)) ENGINE = InnoDB CHARSET=utf8mb4 COLLATE utf8mb4_general_ci;";
	
	SQL_SetCharset(hDB, "utf8mb4");
			
	hDB.Query(OnTableCreate, ListCreateSQL);
	hDB.Query(OnTableCreate, WhitelistCreateSQL);
	hDB.Query(OnTableCreate, LogCreateSQL);
	
	RegPluginLibrary("CIDR_Blocker");

	return APLRes_Success;
}

public void OnTableCreate(Database db, DBResultSet results, const char[] error, any pData)
{
	if (results == null)
		SetFailState("Unable to create table: %s", error);
}

public void OnPluginStart()
{
	LoadToCache();
	LoadToWhitelist();
}

void LoadToCache()
{
	char Select_Query[512];
	
	Format(Select_Query, sizeof Select_Query, "SELECT `cidr`, `kick_message` FROM `cidr_list`");
	
	hDB.Query(SQL_OnLoadToCache, Select_Query);
}

void LoadToWhitelist()
{
	char Select_Query[512];
	
	Format(Select_Query, sizeof Select_Query, "SELECT `type`, `identity` FROM `cidr_whitelist`");
	
	hDB.Query(SQL_OnLoadToWhitelist, Select_Query);
}

public void SQL_OnLoadToCache(Database db, DBResultSet results, const char[] error, any pData)
{
	if (results == null)
		SetFailState("Failed to fetch cache: %s", error); 
		
	CacheRowCount = results.RowCount;
	
	for (int i = 1; i <= CacheRowCount; i++)
	{
		results.FetchRow();
		
		results.FetchString(0, Cache[i][0], sizeof Cache[][]); //CIDR
		results.FetchString(1, Cache[i][3], sizeof Cache[][]); //KICK_MESSAGE
		
		int iStart, iEnd;
		
		ParseCIDR(Cache[i][0], iStart, iEnd);
		
		IntToString(iStart, Cache[i][1], sizeof Cache[][]);
		IntToString(iEnd, Cache[i][2], sizeof Cache[][]);
	}
	
	CacheLoaded = true;
}

public void SQL_OnLoadToWhitelist(Database db, DBResultSet results, const char[] error, any pData)
{
	if (results == null)
		SetFailState("Failed to fetch whitelist: %s", error); 
		
	WhitelistRowCount = results.RowCount;
	
	for (int i = 1; i <= WhitelistRowCount; i++)
	{
		results.FetchRow();
		
		results.FetchString(0, Whitelist[i][0], sizeof Whitelist[][]); //TYPE
		results.FetchString(1, Whitelist[i][1], sizeof Whitelist[][]); //IDENTITY
	}
	
	WhitelistLoaded = true;
}

public void OnClientPostAdminCheck(int client)
{
	if (!CacheLoaded || !WhitelistLoaded)
		return;
	
	if (!IsInWhitelist(client))
	{
		char IP[32];
		
		GetClientIP(client, IP, sizeof IP);
		
		int ID;
		
		if ((ID = IsInRange(IP)) != -1)
			KickClient(client, Cache[ID][3]);
	}
}

bool IsInWhitelist(int client)
{
	char SteamID[32], IP[32];
	
	GetClientAuthId(client, AuthId_Steam2, SteamID, sizeof SteamID);
	GetClientIP(client, IP, sizeof IP);
	
	for (int i = 1; i <= WhitelistRowCount; i++)
	{
		if (StrEqual(Whitelist[i][0], "steam"))
		{
			return StrEqual(Whitelist[i][1], SteamID);
		}
		
		if (StrEqual(Whitelist[i][0], "ip"))
		{
			return StrEqual(Whitelist[i][1], IP);
		}
	}
	
	return false;
}

int IsInRange(const char[] IP)
{
	int iNet = NetAddr2Long(IP), iStart, iEnd;
	
	for (int i = 1; i <= CacheRowCount; i++)
	{
		iStart = StringToInt(Cache[i][1]);
		iEnd = StringToInt(Cache[i][2]);
		
		if (iStart <= iNet && iNet <= iEnd)
			return i;
	}
	
	return -1;
}

stock void ParseCIDR(const char[] sCIDR, int &iStart, int &iEnd)
{
    char Pieces[2][32];
    
    ExplodeString(sCIDR, "/", Pieces, sizeof Pieces, sizeof Pieces[]);
    int baseip = NetAddr2Long(Pieces[0]);
    int prefix = StringToInt(Pieces[1]);
    
    if(prefix == 0) {
        LogError("CIDR prefix 0, clamping to 32. %s", sCIDR);
        prefix = 32;
    }
    
    int shift = 32 - prefix;
    int mask = (1 << shift) - 1;
    int start = baseip >> shift << shift;
    int end = start | mask;
    
    iStart = start;
    iEnd = end;
}

stock int NetAddr2Long(const char[] ip)
{
    char Pieces[4][16];
    int nums[4];

    if (ExplodeString(ip, ".", Pieces, sizeof Pieces, sizeof Pieces[]) != 4)
        return 0;
    
    nums[0] = StringToInt(Pieces[0]);
    nums[1] = StringToInt(Pieces[1]);
    nums[2] = StringToInt(Pieces[2]);
    nums[3] = StringToInt(Pieces[3]);

    return ((nums[0] << 24) | (nums[1] << 16) | (nums[2] << 8) | nums[3]);
}
'********************************************************************
'Troubleshoot Microsoft SCCM client and its health. This script
'Will check BITS, WMI and Client agent components to fix any errors.
'*******************************************************************
    Option Explicit
    Dim eStatus , Final_Status ,IP , SubNet, FSO  
    Dim Admin,WMI,SCCM_AGENT,WSUS_AGENT,HWINV_AGENT_OK,SWINV_AGENT_OK,SWD_AGENT_OK,HWInv_Started,SWInv_Started,SPACE,MP , OUName ,WUASvcExists
    Dim ObjService , colServiceList , objWMIService ,SvcExists , yy ,mm, dd , hh , mi , ss , HWinvOn , SWinvOn , DiscoveryOn,LastSuccessTime2 
    Dim AgtVersion , ComputerName , windir , SysDir, ccmFolder , LastCheckedOn , checkNow , Post , agtConfig, LogonDomain, ContentPath,Disabledcomp
    Dim LogToParse , StrToParse , maxLoop , SiteCode  , CommandLine , GoNext , InstalledOnce , CopyLogs , timeZone , ccmSetupFldr , RegPath , command,CH
    Dim szRegkey,szTemp, szRegpath, Regkey, KeyValue
    Dim inDate ' This variable used in Check4Install function only but needs to refered out side of that.
    Dim LastSuccessTime, SysDate, LastError, Difference, FirstTaskCreatedOn, ResetWMIFlag, ResettingClient, ScTaskcheck , SMonth,SDate,OSversion
	DIM v5_version_mod, client_version, client_version_mod, v5clientcheck, objItem
   
    'INI Variables
    '*************
    DIM Latest_Version, v5_version, chUrl , InvDuration , BITSVersion , CheckFrequency , FSP , CHPostShare , ASiteCode , GPOSiteCode , GetLogs, SchFrequency

    
    Set FSO = CreateObject("Scripting.FileSystemObject")
    Dim net : Set net = CreateObject("Wscript.Network")
    Dim wsh : Set wsh = CreateObject("Wscript.Shell")
    Dim WshNetwork : Set WshNetwork = WScript.CreateObject("WScript.Network")
    
    'SET log files and determine CCM folder
    '*************************************
    Dim strPath , logFile 
    strPath = left(WScript.ScriptFullName,(len(WScript.ScriptFullName)-len(WScript.ScriptName)))
    ComputerName = UCase(net.ComputerName)
    windir = wsh.ExpandEnvironmentStrings("%SystemDrive%")
    SysDir=wsh.ExpandEnvironmentStrings("%SystemRoot%")
    Difference=0
    ScTaskcheck=0

    IF FSO.FolderExists(SysDir&"\SysWOW64") Then 
      ccmFolder =SysDir&"\SysWOW64"
      ccmSetupFldr = SysDir
      RegPath ="HKEY_LOCAL_MACHINE\SOFTWARE\wow6432Node\Microsoft\SMS"
    Elseif FSO.FolderExists(SysDir&"\System32") Then 
      ccmFolder=SysDir&"\System32"
      ccmSetupFldr = SysDir&"\System32"
      RegPath ="HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\SMS"
    End if

    IF NOT FSO.FolderExists(windir &"\Temp\") Then 
        FSO.CreateFolder windir &"\Temp\"
    End if
    OUName = ucase(GETOU)
    Set logFile =FSO.OpenTextFile(windir &"\Temp\" & ComputerName &"."& OUName & ".log",2,True)
    
    'Get INI values
    '**************
    Deb("Initializing the process")
    deb("Strpath : " & strpath)
    if GetInfo <> 1 Then ' Cannot continue
       Deb("MSCH_Retail.INI was not found. Cannot continue..")
       Wscript.quit
    End if ' MSCH.NI check ..... 
    Deb("Collected INI info. Get Logs="&GetLogs)
    '************************************
    'Define Site code and install command
    '************************************
    SiteCode=GetSiteCode(LogonDomain) 
    
    'If there is a GPO assigned site code already then use that one instead of 
    if len(ReadReg(RegPath &"\Mobile Client\GPRequestedSiteAssignmentCode"))=3 then SiteCode =ReadReg(RegPath &"\Mobile Client\GPRequestedSiteAssignmentCode")
    Deb("Site code to assign = "&SiteCode)
    CommandLine= "SMSSITECODE="& SiteCode &" FSP="& FSP &" CCMLOGMAXSIZE=100000 CCMENABLELOGGING=TRUE CCMLOGLEVEL=0 DISABLESITEOPT=TRUE DISABLECACHEOPT=TRUE CCMLOGMAXHISTORY=5 SMSCACHESIZE=10000"
    Deb("Command line to install client:  " &CommandLine)

   
    On Error  resume next
    '*******************************************************************************************************************
    'Check if a successfull check on this machine was done in last "CheckFrequency" number of days. Where the 
    ' "CheckFrequency" being the inventory interval as per in the INI file. If not then proceed or quit the script.
    '*******************************************************************************************************************
    Deb("Reading registry to verify if any successfull check was passed recently.")
    LastCheckedOn=ReadReg(RegPath &"\CH\LastCheckPassedOn")
    LastCheckedOn=Cdate(LastCheckedOn)
    if LastCheckedOn > DateAdd("d",-1*CheckFrequency,now) Then 
      Deb("last check was passed successfully on " &LastCheckedOn ) '& " So not necessary to check now")
      'Wscript.quit
    End if
    
    timeZone = ReadReg("HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\TimeZoneInformation\ActiveTimeBias")
    Deb("Time Zone bias = " &timeZone&" minutes")
    'Deb("No successfull check was passed after "& LastCheckedOn &" which is older than "& DateAdd("d",-1*InvDuration,now) &". So will try it now")
     Post=""
     InstalledOnce=False
     CopyLogs=False
     On Error  goto 0
     if instr(OUName,"WORKSTATIONS.MACHINES.") Then 'Machine is in the supported OU [instr(OUName,".RESEARCH") or instr(OUName,".LABS.") OR ]

         Post="01-1"
         Deb("Machine is in supported OU")
         
		'******************************
		' Check for OS Version
		'*****************************
		
		osversion=ReadReg("HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\CurrentVersion")
		Deb("OS Version = " &OSVersion)        

         
         '*********************************************************************************
         ' Check if the client is installed per registry entries, if not get it installed.
         '*********************************************************************************
         
         '******************************
         ' Check WMI before anything
         '*****************************
         
        If CheckWMI=1 Then ' Only proceed if WMI is started and set to Automatic
            Deb("WMI check passed, now continue...")
            v5checkagent
			If v5clientcheck =1 then
				client_Version=Replace(Client_Version,".","")
				if client_version<>"" then Client_Version=client_Version*1  'pthomsen 8/30/2010 - added IF statement to handle missing client scenario
				v5_version_mod=Replace(v5_Version,".","")
				v5_Version_mod=v5_Version_mod*1
				If client_version<>"" and client_version >= v5_version_mod then  'pthomsen 8/30/2010 - added first clause
					Deb("Client version is V5. Exiting script")
				Else Deb("Agent version is not V5. So proceeding")
					ResetWMIFlag = 0
					CheckAgent ' Will return GoNext = 1 if the client is installed and the version is production version or higher. 
							   ' Will return InstalledOnce =True if successfully Installed. 
							   ' Else will return CopyLogs=True
				End If
		 Else 'v5clientcheck=0
               Deb("WMI check failed")
               GoNext =1
         End if
		End If

         If GoNext = 0 Then
         	'Deb("Function CheckAgent() found error while checking for agents. Creating Scheduled Task to run after "&SchFrequency&" hours.")
         	'Create_SchTask()			
         	WScript.Quit
		else
 		GoNext = 1

         End If

         Else
            Post=Post&"01-0"
             Deb("NON Supported OU "& OUname)
	End If
         
         '*********************************************************************************
         ' If client version is correct then check if it is running/startable. If not Check  WMI.
         ' Install client if WMI is OK and 0 install attempt is made since last <LastCheckedOn> days.
         'If WMI is NOT OK then fix WMI. And install Client if 0 install attempt is made so far. 
         'If any of these tasks failed. Copy the logs and end.
         '*********************************************************************************
                  
         IF GoNext = 1 then ' Version is correct.
            GoNext =0
            'Go to next step Check service
            if CheckSVC("") =1 Then ' All ok
                GoNext = 1
                Deb("CCM service is running fine per WMI")
            Else ' CCM client found to be broken.
                Deb("Could not check CCM service status from WMI. Will try to fix WMI now...")
                If CheckWMI=1 Then ' WMI was off or this check fixed it now.So  Check CCM service one more time and if still failed, try to install the client since client is not ok 
                    if CheckSVC("09") = 1 Then
                        GoNext = 1
                        Deb("CCM service is running fine per WMI after fixing WMI")                    
                    Else ' WMI was able to start. 
                    
                          IF InstalledOnce=False then
                                Deb("Check services failed. Could not start CCM service.Will repair the client now")
								RepairClient
								CopyLogs=True
                          Else ' WMI is OK and also tried to install the client but service is still not starting. So Copy logs and end.
                              CopyLogs=True
                          End if
                    End if
                Else ' WMI is not OK
                    CopyLogs=True
                End if             
            End if 'checkService()
         End if

         '*****************************************************
         'Check client indicators and components block 10,11,14
         '*****************************************************
         IF GoNext = 1 then
            GoNext = 0
       
            if CheckIndicators = 1 then ' All Client indicators and components are ok.
                GoNext =1
                'All check passed at this point. Record that in the registry.
                '*************************************************************
                WriteReg RegPath &"\CH\LastCheckPassedOn", Now, "REG_SZ"
                Post=Post&",20-01"
                Deb("All indicators passed the check")
    
              Else
               Deb("Failed to pass all check indicators")
               CopyLogs=True  
            End if
          End if

         'IF GoNext = 1 then
            'GoNext =0

         'Else
             'Deb("Client failed to pass the indicators and could not trigger any one of the agent could not be triggered" )
         'End if
     
     '*****************************************************************************************************
     'Close the log file, create the post data file and copy it to the network as mentioned in the INI file.
     '*****************************************************************************************************
     
     
     
     '************************************
     'Copy client logs to the network share
     '************************************

     if CopyLogs=True and Ucase(GetLogs)="YES" Then
        CopyClientLogs
     Elseif CopyLogs=True Then
          Deb("End")
          Deb("**************************************************************")
          logFile.Close
          'FSO.CopyFile windir &"\Temp\" & ComputerName &"."& LogonDomain & ".log",CHPostShare
     Else
         Deb("End")
         Deb("**************************************************************")
         logFile.Close
     End if
     Deb(CHUrl&"Post.asp?mn="&ComputerName&"&d="&post)
        
     Set logFile =FSO.OpenTextFile(windir &"\Temp\" & ComputerName &"."& LogonDomain & ".txt",2,True)
     'logFile.WriteLine FormatDateTime(Date(),0) & ">" & post & ">" & agtConfig ' agtConfig will have assigned sitecode,MP,latest HWin , SW inv, SWd and Discovery time
     logFile.WriteLine USDate(now) & ">" & post & ">" & agtConfig ' agtConfig will have assigned sitecode,MP,latest HWin , SW inv, SWd and Discovery time
     
     logFile.Close
     FSO.CopyFile windir &"\Temp\" & ComputerName &"."& LogonDomain & ".txt",CHPostShare

     Wscript.Quit
  

    '******************
    'Sub and Functions
    '******************    

Sub v5CheckAgent()
on error resume next
      '**************************************************************
      ' Check the the existance of v5 client agent and its version
      '**************************************************************
Deb("Running V5checkagent function")
Set objWMIService = GetObject("winmgmts:{impersonationLevel=impersonate}!\\.\root\ccm")
Set colServiceList = objWMIService.ExecQuery ("select * from sms_client")
For Each objItem in colServiceList
	client_version = objitem.Properties_.Item("clientversion").Value
		If err.number = 0 then
			deb("Client version is " & client_version & " as per WMI")
			Post=Post&",03-1H"
			v5clientcheck=1
		Else
			deb("Client version could not be retrieved from WMI" )
			v5clientcheck=1  'pthomsen 8/30/2010 - was set to 0, causing no further client version checking in any scenario
		End if
Next
End Sub

	Sub CheckAgent()
      '**************************************************************
      ' Check the the existance of client agent and its version (2)
      '**************************************************************
      GoNext = 0
      Deb("Executing Sub CheckAgent()")
      AgtVersion =""
      On Error  Resume Next
      Err. clear
      AgtVersion=ReadReg(RegPath &"\Mobile Client\ProductVersion")
      if err.Number <> 0 or AgtVersion ="" then 
              Err.Clear
              AgtVersion=ReadReg("HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\SMS\Mobile Client\ProductVersion")  
      End if
      
      
     if err.Number <> 0 or AgtVersion ="" then AgtVersion=ReadReg("HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\SMS\Mobile Client\ProductVersion")
on error goto 0  'pthomsen 8/30/2010 - otherwise all the following code will not fail if it should
     AgtVersion=Replace(AgtVersion," ","")
     Deb("Agent Version = "&AgtVersion)
     if len(AgtVersion) > 2 then ' Some version of client is installed.
              Post=Post&",02-1"
              eStatus = "Detected client agent service, The version was  "& AgtVersion & " as per registry. The version in production is " & Latest_Version 
              Deb(eStatus)
              eStatus = "Agent version "& AgtVersion &" is equal to or greater than "& Latest_Version &". No need to install/upgrade"
              AgtVersion=Replace(AgtVersion,".","")
              AgtVersion=AgtVersion*1
              Latest_Version=Replace(Latest_Version,".","")
              Latest_Version=Latest_Version*1
              v5_version_mod=""
              v5_version_mod=Replace(v5_Version,".","")
              v5_Version_mod=v5_Version_mod*1
              if AgtVersion > Latest_Version and AgtVersion < v5_version_mod then ' This machine has an higher or equal version of the latest verison as per the INI file.
                    Post=Post&",03-1H" ' Means Higher than production standard.
                    Deb(eStatus)
                    eStatus=""
                    GoNext=1

              Elseif AgtVersion = Latest_Version Then ' No Need to install
                    Post=Post&",03-1S"
                    Deb("NO Version change detected. No need to install client.")
                    GoNext =1              
              Else  ' Deinstall and reinstall
                    Post=Post&",03-0"
                    
                    IF InstalledOnce=False then
                      Deb("Older client version found")
                      Create_SchTask()			
                      If ScTaskcheck=1 Then 'The scheduled task failed to run previously so the install will occur now
                        Deb("Since client is older version, will Uninstall and Re-install client now")
                        If DeInstall("03") = 1 then
                          if Install("04") = 1 then
                              InstalledOnce=True
                          Else
                              CopyLogs=True
                          End if 
                        Else
                          CopyLogs=True
                        End if
                      Else 
                        Deb("End")
                        Deb("**************************************************************")
                        logFile.Close
                        Wscript.Quit

                      End if
                    
                    Else 'not installedonce=false
                      Post=Post&",03-0F"
                      'Wscript.Quit
                    End if
              End if
     Else ' No client is found. Will install now.
         Post=Post&",02-0"
         Deb("No client found. Creating Schedule Task...")
         Create_SchTask()			
         If ScTaskcheck=1 Then                 
           Deb("Still No client found. Will install client now")
          	If InstalledOnce=False then
            	If Install("02") = 1 then 
                	InstalledOnce=True
            	Else
                	CopyLogs=True
            	End if
         	  Else
	            Post=Post&",02-0F"
    	      End If
    	   End If 
     End if
   	On Error  goto 0

End Sub


Function DeInstall(fbn)
   '**********************************************************************************************
   'Uninstall the client if already installed and wait until the uninstallation is complete
   '**********************************************************************************************
   Deb("Executing Function DeInstall(fbn)")
   On Error  Resume Next

   if Check4RecentInstall = 1 then ' The client was installed successfully in last 4 hours. This is to prevent over writing the install via WSUS.
      Deb("A recent (in last 4 hours) successfull installation of the client found in ccmsetup.log. Will not try to install client again")
      Post=Post&","&fbn&"04-00"
      On Error  goto 0
      Exit Function
   End if

   '***************************************************************************************************************
   'Now also check if there was a recent install. In this case should not attempt to uninstall client since the 
   'components take some time to get enabled and a WSUS based install can cause another install this time
   '***************************************************************************************************************

   Deb("Reading registry to verify if any install attempt was made with the last "& CheckFrequency&" days.")
   LastCheckedOn=ReadReg(RegPath &"\CH\LastInstalledOn")
   LastCheckedOn=Cdate(LastCheckedOn)
   if LastCheckedOn > DateAdd("d",-1*CheckFrequency,now) Then 
      Deb("Last install attempt was on " &LastCheckedOn& " Will NOT re-install now.")
      On Error  goto 0
      Exit Function
   End if

   Deb("Reading registry to verify if any uninstall attempt was made with the last "& CheckFrequency&" days.")
   LastCheckedOn=ReadReg(RegPath &"\CH\LastUnInstalledOn")
   LastCheckedOn=Cdate(LastCheckedOn)
   if LastCheckedOn > DateAdd("d",-1*CheckFrequency,now) Then 
      Deb("Last install attempt was on " &LastCheckedOn& " Will NOT uninstall now.")
      Post=Post&","&fbn&"04-0F"
      DeInstall = 2 ' This to not copy logs more than once in last 7 days.
      On Error  goto 0
      Exit Function
   Else
      Deb("Last install attempt was on " &LastCheckedOn& " Will uninstall now.")
      Post=Post & "," & fbn & "04-0S"
      WriteReg RegPath &"\CH\LastUnInstalledOn", Now, "REG_SZ"
   End if
   
   err.Clear
   'Deb("Removing ccmsetup folder")
   KillOldProcess "ccm"
     
   if FSO.FolderExists(ccmSetupFldr&"\CcmSetup") Then
        Wscript.echo TakeOwnerShip(ccmSetupFldr&"\CcmSetup")
        Err.clear  
        'FSO.DeleteFolder ccmSetupFldr&"\CcmSetup",True
    End if
    IF err.Number=0 Then
      Deb("CCMSetup Folder deleted Successfully or did not exist.")
      Post=Post&","&fbn&"04-1S"
    Else
      Deb("Couldnot Delete CCMSetup Folder. Error Was " &Err.Description)
      Post=Post&","&fbn&"04-1F"
    End if

   Deb("UnInstalling client")
   Err.Clear     
   'Add the server name in to the trusted site
   WriteReg "HKEY_USERS\S-1-5-18\Software\Microsoft\Windows\CurrentVersion\Internet Settings\ZoneMap\Domains\microsoft.com\*.corp\*","1","REG_DWORD" 
   WriteReg "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Internet Settings\ZoneMap\Domains\microsoft.com\*.corp\*","1","REG_DWORD" 
   
   Deb("Executing command \\"&LogonDomain&"\NetLogon"&ContentPath&"\ccmSetup.exe /Uninstall")
   WSH.Run("\\"&LogonDomain&"\NetLogon"&ContentPath&"\ccmSetup.exe /Uninstall"), 0,True
   'Deb("Executing command \\RED-TP-REPORT\CP\MSCH\6221\ccmSetup.exe /Uninstall")
   'WSH.Run("\\RED-TP-REPORT\CP\MSCH\6221\ccmSetup.exe /Uninstall"), 0,True

   IF err.Number=0 Then
      ' Check the client is deleted.
      Deb("Checking CCMSetup.log for status")
      
      If  ReadLog(ccmSetupFldr&"\CcmSetup\CCMSetup.Log" , "Uninstall succeeded.") = 1 Then
          Deb("Uninstall Sucess as per CCMSetup.log")
          Post=Post&","&fbn&"04-2S"' Means Uninstall success
          err.Clear
          Deb("Removing CCM folder")
          KillOldProcess "ccm"
          'if FSO.FolderExists(ccmFolder&"\Ccm") Then FSO.DeleteFolder ccmFolder&"\Ccm",True
          'IF err.Number=0 Then
           '  Post=Post&","&fbn&"04-3S"
           '  Deb("CCM Folder deleted Successfully or did not exist.")
          'Else
           '  Post=Post&","&fbn&"04-3F"
           '  Deb("Couldnot Delete CCM Folder. Error Was " &Err.Description)
          'End if
          
          Deb("Removing SMS Registry")
          Err.Clear
          
          DeleteReg("HKLM\SOFTWARE\Microsoft\SMS")
          
          IF err.Number=0 Then
             Post=Post&","&fbn&"04-4S"
             Deb("SMS registry deleted Successfully or did not exist.")
          Else
             Post=Post&","&fbn&"04-4F"
             Deb("Couldnot Delete SMS Registry Key, error Was " &Err.Description)
          End if
        
          DeInstall=1
       Else
          Post=Post&","&fbn&"04-2F"' ' Means Failed to uninstall
	  Deb("Uninstalltion of client failed")
          DeInstall=0
       End if
   End if
   On Error  GOTO 0
End Function

Function Install(fbn)

   On Error  Resume Next
   Deb("Executing Function Install("&fbn&")")
   InstalledOnce=True
   Dim LastInstallTime  
  
   if Check4RecentInstall = 1  Then ' The client was installed successfully in last 4 hours. This is to prevent over writing the install via WSUS.
      Deb("A recent (in last 4 hours) successfull installation of the client found in ccmsetup.log. Will not try to install client again")
      Post=Post & "," & fbn & "05-00"
      On Error  goto 0
      Exit Function
   End if

   Deb("Reading registry to verify if any install attempt was made with the last "& CheckFrequency&" days.")
   LastCheckedOn=ReadReg(RegPath &"\CH\LastInstalledOn")
   LastCheckedOn=Cdate(LastCheckedOn)
   if LastCheckedOn > DateAdd("d",-1*CheckFrequency,now) Then 
      Deb("Last install attempt was on " &LastCheckedOn& " Will Not install now.")
      Post=Post&","&fbn&"05-0F"
      Install = 2 ' This is to not copy logs more than once in last '7' days.
      On Error  goto 0
      Exit Function
   Else
		FirstTaskCreatedOn=ReadReg(RegPath &"\CH\SchTaskCreatedOn")
		Difference = DateDiff("h",FirstTaskCreatedOn, Now())
		 If (FirstTaskCreatedOn = "" or (clng(Difference) < CLng(SchFrequency))) And ScTaskcheck=0 Then
		
	      Deb("No recent install was found. This might be new machine, creating scheduled task to execute after "&SchFrequency&" hours.")
	      Create_SchTask()	      
	      Wscript.Quit
			
		Else 
   
   
   err.Clear   
   Deb("The Scheduled task is already created on "&FirstTaskCreatedOn&" which is greater than"&SchFrequency&"hour(S)") 
   Deb("Installing client")
   err.Clear
   'Deb("Removing ccmsetup folder")
   KillOldProcess "ccm"
     
   if FSO.FolderExists(ccmSetupFldr&"\CcmSetup") Then
         TakeOwnerShip(ccmSetupFldr&"\CcmSetup")  
         'FSO.DeleteFolder ccmSetupFldr&"\CcmSetup",True
         IF err.Number=0 Then
            Deb("CCMSetup Folder deleted Successfully or did not exist.")
            Post=Post&","&fbn&"05-1S"
         Else
            Deb("Could not Delete CCMSetup Folder '" & ccmSetupFldr&"\CcmSetup' Error Was " & Err.Description)
            Post=Post&","&fbn&"05-1F"
            err.clear
         End if        
         'FSO.DeleteFile ccmSetupFldr&"\CcmSetup\ccmSetup.log",True
    End if

      
   err.Clear
   Deb("Removing CCM folder")
   
   if FSO.FolderExists(ccmFolder&"\Ccm") Then 
        TakeOwnerShip(ccmFolder&"\Ccm") 
        'FSO.DeleteFolder ccmFolder&"\Ccm",True
    End if
    IF err.Number=0 Then
        Post=Post&","&fbn&"05-2S"
        Deb("CCM Folder deleted Successfully or did not exist.")
    Else
        Post=Post&","&fbn&"05-2F"
        'Deb("Couldnot Delete CCM Folder. Error Was " &Err.Description)
    End if
             
   'Add the server name in to the trusted site. This is to avoid prompting for user input.
   WriteReg "HKEY_USERS\S-1-5-18\Software\Microsoft\Windows\CurrentVersion\Internet Settings\ZoneMap\Domains\microsoft.com\*.corp\*","1","REG_DWORD" 
   WriteReg "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Internet Settings\ZoneMap\Domains\microsoft.com\*.corp\*","1","REG_DWORD" 
   
   Err.Clear
   LastInstallTime = Now
   Deb("Executing command \\"&LogonDomain&"\NetLogon"&ContentPath&"\ccmSetup.exe /Service " &CommandLine)
   WSH.Run("\\"&LogonDomain&"\NetLogon"&ContentPath&"\ccmSetup.exe /Service " &CommandLine), 0,True
   'Deb(" Executing \\RED-TP-REPORT\CP\MSCH\6221\ccmSetup.exe /Service " &CommandLine)
   'WSH.Run("\\RED-TP-REPORT\CP\MSCH\6221\ccmSetup.exe /Service " &CommandLine), 0,True
   
   if err.Number <> 0 then 
       Post=Post&","&fbn&"05-3F"  ' Means Client install command failed
       Deb("Client install failed. Creating Scheduled Task to run after "&SchFrequency&" hours.")
       Create_SchTask()
       Wscript.Quit
    Else
       Post=Post&","&fbn&"05-3S" ' Means client install command success
       Deb("Client install initiated successfully.")
       maxLoop=1
       Install=0
       
       Deb("Last install date as per ccmsetup.log ='"& inDate &"'. Ignore if it is empty")
       Do while True 
           'IF ReadLog(ccmSetupFldr&"\CcmSetup\CCMSetup.Log" , "Installation succeeded.") = 1 Then
           IF Check4RecentInstall =1 then 
                if Cdate(inDate) > Cdate(LastInstallTime) Then ' install success
                    Deb("The latest install time ="& inDate)
                    Post=Post&","&fbn&"05-4S"
                    Install=1
                    Deb("Client install completed successfully as per " & ccmSetupFldr & "\CcmSetup\CCMSetup.Log")
                    Exit Do
                Else
                    if maxLoop>20 then 
                        Deb("Did not succeed after "& maxLoop-1 &" number of check cycles")
                        Exit do 
                    End if
                    maxLoop=maxLoop+1
                    Wscript.Sleep 1000*60
                End if
           Else
                if maxLoop>20 then 
                    Deb("Did not succeed after "& maxLoop-1 &" number of check cycles")
                    Exit do 
                End if
                maxLoop=maxLoop+1
                Wscript.Sleep 1000*60
           End if
       Loop
       If inStr(Post,"05-4S") Then ' Install success
       Else
          Post=Post&","&fbn&"05-4F"
       End if
    End if
	end if
	end If

    On Error  GOTO 0
End Function

Sub Deb(Message)
    On Error  Resume Next
    If IsObject(logFile) Then
       logFile.WriteLine  Now & " - " & Message
    End If
    On Error  goto 0
    eStatus=""
End sub

Function WriteReg(RegPath, Value, RegType)
      On Error  Resume Next
      Deb("Executing Function WriteReg("&RegPath&", "&Value&", "&RegType&")")
      err.clear
      Dim objRegistry, Key
      Set objRegistry = CreateObject("Wscript.shell")
      Key = objRegistry.RegWrite(RegPath, Value, RegType)
      WriteReg = Key
      On Error  goto 0
End Function

Function ReadReg(RegPath)
      On Error  Resume Next
      ReadReg = 0
      Deb("Executing Function ReadReg("&RegPath&")")
      err.clear
      Dim objRegistry, Key
      Set objRegistry = CreateObject("Wscript.shell")
      Key = objRegistry.RegRead(RegPath)
      ReadReg = Key
      if err.number <> 0 then Deb("it seems registry key " & RegPath & " doesn't exist.")
      On Error  goto 0
End Function

Function WMIReadReg(szRegpath)
	Deb("Executing Function WMIReadReg("&szRegPath&")")
	WMIReadReg=0
	Const HKEY_LOCAL_MACHINE   = &H80000002
	Dim f_ClassId,f_RegRoot,f_strTemp,f_strKeyPath,f_ProcessorArch,intReturn
	Dim objCtx,objLocator,objServices,objStdRegProv,oWSH
	Dim c_strComputer

	szRegkey=szRegpath
	c_strComputer="."
	Err.Clear
	f_ClassId      = Right(szRegkey,Len(szRegkey)-InstrRev(szRegkey,"\"))
	f_RegRoot      = Left(szRegkey,Instr(szRegkey,"\") - 1)
	f_strTemp     = Mid(szRegkey,Instr(szRegkey,"\") + 1)
	f_strKeyPath = Mid(f_strTemp,1,InstrRev(f_strTemp,"\") - 1)
	Err.Clear 
	   
	Set objCtx = CreateObject("WbemScripting.SWbemNamedValueSet")
		objCtx.Add "__ProviderArchitecture", 64
	Err.Clear
		Set objLocator = CreateObject("Wbemscripting.SWbemLocator")
	Set objServices = objLocator.ConnectServer(c_strComputer,"root\default","","",,,,objCtx)
	Set objStdRegProv = objServices.Get("StdRegProv") 
	Err.Clear
	If instr(SzRegpath,"Lasterror") then

	intReturn = objStdRegProv.GetDWordValue(Eval(f_RegRoot),f_strKeyPath,f_ClassId,szTemp)
	else 
	intReturn = objStdRegProv.GetStringValue(Eval(f_RegRoot),f_strKeyPath,f_ClassId,szTemp)

	end if
	if err.number <> 0 then Deb("it seems registry key " & RegPath & " doesn't exist.")
	WMIReadReg=szTemp
	On Error  goto 0
End Function


Function DeleteReg(RegPath)
      On Error  Resume Next
      Deb("Executing Function DeleteReg("&RegPath&")")
      err.clear
      Dim objRegistry, Key
      Set objRegistry = CreateObject("Wscript.shell")
      Key = objRegistry.RegDelete(RegPath)
      DeleteReg = Key
      On Error  goto 0
End Function


Function GetOU()

    On Error  Resume Next
    Deb("Executing Function GetOU()")
    Dim objSysInfo , strComputer , arrOUs , objComputer
    Set objSysInfo = CreateObject("ADSystemInfo")
    strComputer = objSysInfo.ComputerName
    Set objComputer = GetObject("LDAP://" & strComputer)
    arrOUs = Ucase(objComputer.Parent)
    LogonDomain=Replace(arrOUs,",DC=",".")
    LogonDomain=Mid(LogonDomain,instr(LogonDomain,".")+1,len(LogonDomain))
    arrOUs = Replace(arrOUs,",OU=",".")
    arrOUs = Replace(arrOUs,",DC=",".")
    arrOUs = Replace(arrOUs,"LDAP://OU=","")
    GetOU=Replace(arrOUs,",OU=",".")
    On Error  goto 0
End Function

Function  GetInfo()
      'Latest_Version , chUrl , InvDuration , BITSVersion, v5_version
      On Error  Resume Next
      GetInfo=1
      Deb("Executing Sub GetInfo()")
      Dim INIFile , INILine , INIValues
      IF FSO.FileExists(strPath & "MSCH_Retail.INI") Then
         
      Else
          Deb(strPath & "MSCH_Retail.INI not found")
          On Error  goto 0
          GetInfo =0
          Exit Function
      End if
      Set INIFile =FSO.OpenTextFile(strPath & "MSCH_Retail.INI",1)
      Do while INIFile.AtEndOFStream <> True
        INILine = lcase(INIFile.ReadLine)
        INILine = Replace(INILine," ","")
        INIValues=Split(INILine,"=")
        select case INIValues(0)
          CASE Lcase("Latest_Version")
          Latest_Version = INIValues(1) 
          CASE Lcase("v5_Version")
          v5_Version = INIValues(1) 
		  CASE Lcase("chUrl")
          chUrl= INIValues(1)
          CASE Lcase("InvDuration")
          InvDuration = INIValues(1)
          CASE Lcase("BITSVersion")
          BITSVersion = INIValues(1)
          CASE Lcase("CheckFrequency")
          CheckFrequency = INIValues(1) 
          CASE Lcase("ContentPath")
          ContentPath = INIValues(1)
          CASE Lcase("FSP")
          FSP=INIValues(1) 
          CASE Lcase("CHPostShare")
          CHPostShare=INIValues(1)
          CASE Lcase("GetLogs")
          GetLogs=INIValues(1)   
          CASE LCase("SchFrequency")
          SchFrequency=INIValues(1)
        End Select 
      Loop
      INIFile.Close
      On Error  goto 0
End Function

Function ReadLog(Fname,strName)
    On Error  resume next
    Deb("Executing Function ReadLog(Fname,strName)")
    Err.Clear
    SET LogToParse = FSO.OpenTextFile(Fname,1,False)
    StrToParse=LogToParse.ReadAll
    LogToParse.Close
    If Instr(StrToParse,strName) Then
        ReadLog=1
    Else
        ReadLog=0
    End if
    StrToParse=""
    On Error  goto 0
End Function

Function TakeOwnerShip(fdr)
      
      On Error  resume next
      fdr=Replace( fdr,"\","\\")
      fdr = chr(34)&fdr&chr(34)
      Deb("Executing Function TakeOwnerShip("&fdr&")")
      err.clear
      Dim objWMI , objFile , intRC
      Dim colFolders , objFolder 
      Deb("The WMI Query for the folder is : Select * From Win32_Directory Where Name = " & fdr)
      Set objWMI = GetObject("winmgmts:\\.\root\cimv2")
      Set colFolders = objWMI.ExecQuery _
          ("Select * From Win32_Directory Where Name = " & fdr )

      For Each objFolder in colFolders
          Wscript.echo objFolder.Name
          intRC = objFolder.TakeOwnershipEx
      Next
      if intRC = 0 then ' Took ownership ok
         Deb("File ownership successfully changed for "&fdr)
         TakeOwnerShip=1
      else
         Deb("Error transferring file ownership of "&fdr&"   " & err.number)
         TakeOwnerShip=0
      end if
      On Error  goto 0
End Function

Sub KillOldProcess(pname)
      On Error  resume next
      Deb("Executing Sub KillOldProcess("&pname&")")
      Dim objWMIService , colProcessList ,  objProcess , createDate , yy ,mm,dd,hh, mi,ss , mname
      Set objWMIService = GetObject("winmgmts:{impersonationLevel=impersonate}!\\.\root\cimv2")
      Set colProcessList = objWMIService.ExecQuery ("Select * from Win32_Process Where CommandLine like '%"&pname&"%'")
      For Each objProcess in colProcessList
         objProcess.Terminate()
      Next
      On Error  goto 0
End Sub

Function CheckSVC(fbn)
    CheckSVC=0
    Deb("Executing Function CheckSVC(fbn)")
    Dim rrReturn
    On Error  resume next

    err.Clear
    '**********
    'Check WSUS
    '**********
    Set objWMIService = GetObject("winmgmts:{impersonationLevel=impersonate}!\\" & ComputerName & "\root\cimv2")

    If err.Number=0 Then ' WMI is working at least to the base classes 
        Post=Post&","&fbn&"06-1S"

        '***********************
        '\\\ Check WSUS service
        '***********************
        Err.Clear
        Set colServiceList = objWMIService.ExecQuery ("SELECT * FROM Win32_Service WHERE Name='wuauserv'")
        If err.Number=0 Then
            Post=Post&","&fbn&"06-2S"
        Else
            Post=Post&","&fbn&"06-2F"
        End if
        Err.Clear
        WSUS_AGENT=False
        WUASvcExists="No"
        Deb("Checking WSUS service")
        For Each objService in colServiceList
            WUASvcExists="Yes"
            WSUS_AGENT=ObjService.Started
            if WSUS_AGENT=False then
                Post=Post&","&fbn&"06-3F"
                rrReturn=1
                rrReturn = objService.ChangeStartMode("Automatic")
                Wscript.Sleep 1500
                if rrReturn =0 Then
                    Post=Post&","&fbn&"06-4S"
                Else
                    Post=Post&","&fbn&"06-4F"
                End if
                rrReturn=1
                rrReturn = objService.StartService()
                Wscript.Sleep 1500

                if rrReturn =0 Then
                    Post=Post&","&fbn&"06-5S"
                Else
                    Post=Post&","&fbn&"06-5F"
                End if
                
            Else
                Post=Post&","&fbn&"06-3S"
            End if
        Next
        
        If err.Number=0 Then
            Post=Post&","&fbn&"06-6S"
        Else
            Post=Post&","&fbn&"06-6F"
            Deb("Checking WSUS service in WMI failed, "&err.number&",   "&err.description&".")
        End if
        Err.Clear
        
        If WUASvcExists ="No" Then ' WSUS service doesnot exist!!
           Post=Post&","&fbn&"06-7F"
           Deb("WSUS service not found")
        End If

        
        '***************************************************************************
        '\\ Check and start CCM . If service doesn't exist then attempt to install 
        '***************************************************************************

        Err.Clear
        Set colServiceList = objWMIService.ExecQuery ("SELECT * FROM Win32_Service WHERE Name='CcmExec'")
        If err.Number=0 Then
            Post=Post&","&fbn&"07-1S"
        Else
            Post=Post&","&fbn&"07-1F"
        End if
        Err.Clear
        WSUS_AGENT=False
        SvcExists="No"
        Deb("Checking CCM service")
        For Each objService in colServiceList
            SvcExists="Yes"
            SCCM_AGENT=ObjService.Started
            if SCCM_AGENT=False then
                Deb("CCM Service was not running")
                Post=Post&","&fbn&"07-2F"
                rrReturn=1
                rrReturn = objService.ChangeStartMode("Automatic")
                Wscript.Sleep 1500
                if rrReturn =0 Then
                    Post=Post&","&fbn&"07-3S"
                Else
                    Post=Post&","&fbn&"07-3F"
                End if
                rrReturn=1
                rrReturn = objService.StartService()
                Wscript.Sleep 1500

                if rrReturn =0 Then
                    Post=Post&","&fbn&"07-4S"
                    Deb("CCM started successfully")
                Else
                    Post=Post&","&fbn&"07-4F"
                End if
                
            Else
                Post=Post&","&fbn&"07-2S"
            End if
        Next
        
        If err.Number=0 Then
            Post=Post&","&fbn&"07-5S"
        Else
            Post=Post&","&fbn&"07-5F"
            Deb("Checking CCM service in WMI failed, "&err.number&",   "&err.description&".")
        End if
        Err.Clear
        
        If SvcExists ="No"  Then ' CCM service doesnot exist 
           Post=Post&","&fbn&"07-7F"
           'Deinstall and install client if did NOT do it already. Or FIX WMI and install client.
           Deb("CCM service not found per WMI")
           
        Elseif SCCM_AGENT=False and rrReturn <> 0  then ' could not start!! 
            'Fix WMI and Install client.
            Deb("Could not start CCM Service")
        Else
            CheckSVC=1
            'Deb("CCM Service is running fine")
        End If

    Else ' WMI is not working or a firewall is blocking. Check the error code in WMI column.
        Post=Post&","&fbn&"06-1F"
        Deb("Failed to connect to WMI to check services "&err.number&",   "&err.description)
        'Fix Wmi
    End if
    On Error  goto 0
End Function

Function CheckWMI()
    On Error  resume next
    Deb("Executing Function CheckWMI()")
    CheckWMI=1
    Post=Post&",08-1"
    Deb("Checking WMI Service....")
    
    Dim ComputerObj , Service , wService , ccmsvc , objService
    Set ComputerObj =  GetObject("WinNT://" & WshNetwork.ComputerName & ",computer")
    Set objService = ComputerObj.GetObject("service", "Winmgmt")

    Deb("Service Start Type  ="&objService.StartType&"    Service status  ="&objService.Status)
        
        
    If objService.Status <> 4 Then  objService.Status =4
    If objService.StartType <> 2 Then  objService.StartType = 2    
    objService.SetInfo

    Deb("Service Start Type set to "&objService.StartType&"    Service status set to "&objService.Status)


    ComputerObj.Filter = Array("Service")
    For Each Service in ComputerObj
        if Lcase(Service.Name) = Lcase("Winmgmt") then 
             If Service.Status <> 4 then ' Not running
                Deb("Found WMI not running")
                Post=Post&",08-1F"
                Set wService = GetObject("WinNT://./"&Service.Name&",Service")
                if WriteReg("HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\services\Winmgmt\Start", "2", "REG_DWORD") = 0 Then 
                    Deb("Set WMI service start type to auto......")
                End if
                Wscript.sleep 1000
                wService.Start
                Wscript.sleep 20000
                if Service.Status = 4 Then 
                    Post=Post&",08-2S"
                    Deb("WMI started")
                Else
                    Post=Post&",08-2F"
                    Deb("Failed to start WMI....")
                    CheckWMI=0
                End if 
                'Check the status of the CCMExec service and remediate
				Set wService = GetObject("WinNT://./ccmexec,Service")
                wService.Start
                Wscript.sleep 5000
                For Each ccmsvc in ComputerObj
                    if Lcase(ccmsvc.Name) = Lcase("CCMExec") then 
                         if ccmsvc.Status = 4 Then 
                            Post=Post&",08-3S" 
                         Else
                            Post=Post&",08-3F"
                         End if
                         if ccmsvc.startType<> 2 then ' CCM NOt set to automatic
                            Post=Post&",08-6F"
                            if WriteReg("HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\services\CcmExec\Start", 2, "REG_DWORD") = 0 Then 
                                Post=Post&",08-7S"
                                Deb("Attempt to set the CCM service to auto was not success. This may cause to re-install the the client")
                            Else
                                Post=Post&",08-7F"
                            End if
                         Else
                            Post=Post&",08-6S"
                         End if
                         Exit For
                    End if
                Next
             Else
                Post=Post&",08-1S"
             End if
             'Check if WMI is set to Auto
             if Service.startType<> 2 then ' WMI NOT set to automatic
                Post=Post&",08-4F"
                if WriteReg("HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\services\Winmgmt\Start", 2, "REG_DWORD") = 0 Then 
                    Post=Post&",08-5S"
                Else
                    Post=Post&",08-5F"
                    CheckWMI=0
                    Deb("Attempt to set the WMI service to auto was not successful. This may cause to re-install the the client")
                End if
             Else
                Post=Post&",08-4S"
             End if
             Exit for
        End if
    Next 
    On Error  goto 0
End Function     

Function CollectLogs
    
    On Error  Resume Next
    Deb("Executing Function CollectLogs")
    Err.clear
    Dim nf ,r , e
    e=0
    Post=Post&",21-01"
    Deb("Storing client logs")
    'Create a local store to copy the files
    Err.clear
    if fso.FolderExists(windir &"\Temp\" & ComputerName &"."& LogonDomain) Then 
        fso.DeleteFolder windir &"\Temp\" & ComputerName &"."& LogonDomain, True
        fso.DeleteFile windir &"\Temp\" & ComputerName &"."& LogonDomain&".zip", True
    End if
    Set nf = FSO.CreateFolder(windir &"\Temp\" & ComputerName &"."& LogonDomain)
  
    Deb("File store folder is "&nf)
    If Err.Number <> 0 then 
      Post=Post&",21-02F"
      Deb("Failed to create folder for file store. An error "&Err.Number&" occured. Description "&Err.Description)
      e=1
    Else
      Post=Post&",21-02S"
    End if
    
    'Create REG.TXT
    Err.clear
    SET r = FSO.OpenTextFile(windir &"\Temp\r.bat",2,True)
    r.WriteLine "REG QUERY hklm\software\microsoft\sms /s > " & windir &"\Temp\" & ComputerName &"."& LogonDomain &"\Reg.txt"
    r.Close
    SET r= Nothing
    WSH.Run(windir &"\Temp\r.bat"), 0,True
    fso.DeleteFile windir &"\Temp\r.bat", True
    
    If Err.Number <> 0 then 
      Post=Post&",21-03F"
      Deb("Failed to collect registry details.An error "&Err.Number&" occured. Description "&Err.Description)
      e=1
    Else
      Post=Post&",21-03S"
    End if
    
    'Copy CCM Set up logs
    Err.clear
    FSO.CopyFile ccmSetupFldr&"\CcmSetup\ccmsetup.log",nf&"\"

    If Err.Number <> 0 then 
      Post=Post&",21-04F"
      Deb("Failed to collecte ccmsetup.log. An error "&Err.Number&" occured. Description "&Err.Description)
      e=1
    Else
      Post=Post&",21-04S"
    End if

    'Collect CCMExec logs
    Err.clear
    FSO.CopyFile ccmFolder&"\ccm\logs\CcmExec.log",nf&"\"
    If Err.Number <> 0 then 
      Post=Post&",21-05F"
      Deb("Failed to collect ccmExec.log. An error "&Err.Number&" occured. Description "&Err.Description)
      e=1
    Else
      Post=Post&",21-05S"
    End if
    
    'Collect Location Services Log
    Err.clear    
    FSO.CopyFile ccmFolder&"\ccm\logs\LocationServices.log",nf&"\"
    If Err.Number <> 0 then 
      Post=Post&",21-06F"
      Deb("Failed to collect LocationService.log. An error "&Err.Number&" occured. Description "&Err.Description)
      e=1
    Else
      Post=Post&",21-06S"
    End if

    'Collect FTP state message logs
    Err.clear
    FSO.CopyFile ccmFolder&"\ccm\logs\FSPStateMessage.log",nf&"\"
    If Err.Number <> 0 then 
      Post=Post&",21-07F"
      Deb("Failed to collect FSPStateMessage.log. An error "&Err.Number&" occured. Description "&Err.Description)
      e=1
    Else
      Post=Post&",21-07S"
    End if
    
    'Collect WindowsUpdate logs
    Err.clear
    FSO.CopyFile SysDir &"\WindowsUpdate.log",nf&"\"

    If Err.Number <> 0 then 
      Post=Post&",21-08F"
      Deb("Failed to collect WindowsUpdate.log. An error "&Err.Number&" occured. Description "&Err.Description)
      e=1
    Else
      Post=Post&",21-08S"
    End if
    Err.clear
    
    FSO.CopyFile ccmFolder&"\ccm\logs\ClientIDManagerStartup.log",nf&"\"
    If Err.Number <> 0 then 
      'Post=Post&",21-07F"
      Deb("Failed to collect ClientIDManagerStartup.log. An error "&Err.Number&" occured. Description "&Err.Description)
      e=1
    Else
      'Post=Post&",21-07S"
    End if
        

    
    'Set return values
    Err.clear
    if e=0 then 
        CollectLogs=1
        Deb("Log collection completed successfully")
    Else
        CollectLogs=0
        Deb("At least one Log collection falied")
    End if
      
    'Copy this script logs itself
    Err.clear
    Deb(CHUrl&"Post.asp?mn="&ComputerName&"&d="&post)
    Deb("This log file is being copied to the server for verificaiton. Few entries after this point will not be in this log. But will be available in the database.")
    
    FSO.CopyFile windir &"\Temp\" & ComputerName &"."& OUName & ".log", nf&"\"
    If Err.Number <> 0 then 
      Post=Post&",21-10F"
      e=1
    Else
      Post=Post&",21-10S"
    End if
    
    On Error  goto 0
End Function

Function ZipIt(ZipFile,FileName)
      On Error  Resume Next
      Deb("Executing Function ZipIt(ZipFile,FileName)")
      
      Dim e 
      err.Clear
      If FSO.FileExists(ZipFile) Then ' Delete first
        FSO.DeleteFile ZipFile
      End IF
          
      '-------------- create empty zip file ---------
      'Create the basis of a zip file.
      err.Clear
      CreateObject("Scripting.FileSystemObject") _
       .CreateTextFile(ZipFile, True) _
       .Write "PK" & Chr(5) & Chr(6) & String(18, vbNullChar)
      
      If Err.Number <> 0 then 
        Post=Post&",21-30F"
        e=1
      Else
        Post=Post&",21-30S"
      End if      

      Const FOF_CREATEPROGRESSDLG = &H0&

      '-------------- zip ---------------------------

      'get ready to add files to zip
      err.Clear
      With CreateObject("Shell.Application")
          'add files
          .NameSpace(ZipFile).CopyHere FileName, FOF_CREATEPROGRESSDLG
      End With
      wScript.Sleep 5000
      
      If Err.Number <> 0 then 
        Post=Post&",21-31F"
        e=1
      Else
        Post=Post&",21-31S"
      End if
      if e=0 then 
          ZipIt=1
      Else
          ZipIt=0
      End if

      On Error  goto 0
End Function


Sub CopyClientLogs

    On Error  Resume Next
    Deb("Executing Sub CopyClientLogs")
    Deb("Reading registry to verify if any log copy  attempt was made with the last "& CheckFrequency&" days.")
    LastCheckedOn=ReadReg(RegPath &"\CH\LogsCopiedOn")
    LastCheckedOn=Cdate(LastCheckedOn)
    if LastCheckedOn > DateAdd("d",-1*CheckFrequency,now) Then 
      Deb("Last Log copy attempt was on " &LastCheckedOn& " Will Not copy again at this time.")
      Post=Post&",21-0F"
      On Error  goto 0
      Exit Sub
    Else
      Deb("Last Log copy attempt was on " &LastCheckedOn)
    End if
       
    
    Err.clear
    Dim nf  , e
    e=0
    Post=Post&",21-00"
    Deb("Copying client logs")
    'Check if the last copy file copy was done within the pre determined time and do not copy .
     IF CollectLogs = 1 Then ' Log collection success. Now try to zip it and copy to the server
        Post=Post&",21-40S"
        Deb("Logs collected successfully. Compress logs now.")
        If ZipIt  (windir &"\Temp\" & ComputerName &"."& LogonDomain &".zip" , windir &"\Temp\" & ComputerName &"."& LogonDomain) =1 Then 'Compression success
            Deb("Successfully compressed logs")
            Err.clear
            FSO.CopyFile  windir &"\Temp\" & ComputerName &"."& LogonDomain &".zip" , CHPostShare , True 
            if err.Number <> 0 then 
                e=1
                Deb("Error copying logs, error Number was "&err.Number)
                'Deb("Copy "&windir &"\Temp\" & ComputerName &"."& LogonDomain&".zip" &" "& CHPostShare)
                'Wsh.Run("Copy "&windir &"\Temp\" & ComputerName &"."& LogonDomain&".zip" &" "& CHPostShare)
            End if
            Post=Post&",21-41"
        Else ' Failed to compress so copy the folder itself. 
            Err.clear
            Deb("Failed to compress logs")
            FSO.CopyFolder  windir &"\Temp\" & ComputerName &"."& LogonDomain , CHPostShare , True 
            if err.Number <> 0 then 
                e=1
                Deb("Failed to copy logs. Error Number was " &Err.Number)
            End if
            Post=Post&",21-42"
        End if 
     
     Elseif FSO.FolderExists(windir &"\Temp\" & ComputerName &"."& LogonDomain) Then ' The folder is created and at least some files are in there
        Deb("Some logs did not exist or failed to collect. Compress logs now.")
        Post=Post&",21-40F"
        If ZipIt  (windir &"\Temp\" & ComputerName &"."& LogonDomain &".zip" , windir &"\Temp\" & ComputerName &"."& LogonDomain) =1 Then 'Compression success
            Deb("Successfully compressed logs")
            Err.clear
            FSO.CopyFile  windir &"\Temp\" & ComputerName &"."& LogonDomain &".zip" , CHPostShare , True
            if err.Number <> 0 then 
                e=1
                Deb("Error copying logs, error Number was "&err.Number)
            End if
            Post=Post&",21-41"
        Else ' Failed to compress so copy the folder itself. 
            Err.clear
            Deb("Failed to compress logs")
            FSO.CopyFolder  windir &"\Temp\" & ComputerName &"."& LogonDomain , CHPostShare , True 
            if err.Number <> 0 then 
                e=1
                Deb("Failed to copy logs. Error Number was " &Err.Number)
            End if
            Post=Post&",21-42"
        End if
     Else
        Post=Post&",21-43"
     End if
     
     If e= 0 then ' Successfully copied the files
        Post=Post&",21-44S"
        WriteReg RegPath &"\CH\LogsCopiedOn", Now, "REG_SZ"
        Deb("Successfully copied log files")
     Else
        Post=Post&",21-44F"
        'Deb("Failed to copy logs. Error was "&Err.Description)
     End if
     On Error  goto 0
End Sub


Function CheckIndicators()
      flag = 1 
      Deb("Executing Function CheckIndicators()")     
      Dim SMSClient , HWinvOn , SWinvOn , DiscoveryOn , objService , flag
      Dim objWMIService2, colItems1, LastReplyTime, objItem1

      On Error  resume next
      err.clear
      Post=Post&",10-00"
      Deb("Checking Client health indicators.......")

      Set objWMIService = GetObject("winmgmts:{impersonationLevel=impersonate}!\\.\root\ccm\invagt")
      if Err.Number <> 0 then
          Deb("An error "&err.number&",   '"&err.description&"' occured while connecting to \root\ccm\invagt.......")
          Post=Post&",10-00F"
          flag = 0
          'pthomsen 8/31/2010 - next two lines added. If the namespace isn't available then WMI should be fixed, and that should be done before repairing the client
          VerifyWMI
          If ResetWMI then RepairWMI
          RepairClient
      Else
          Err.Clear
          Post=Post&",10-00S"
          Deb("Connection to invAgt success")
          Set colServiceList = objWMIService.ExecQuery ("Select * from InventoryActionStatus")
          if Err.Number <> 0 then
              Deb("An error "&err.number&",   '"&err.description&"' occured while reading InventoryActionStatus.......")
              Post=Post&",10-01F"
              flag =0
              Err.Clear
              
          Else
              Err.Clear
              Deb("Successfully connected to InventoryActionStatus")
              Post=Post&",10-01S"
              HWinvOn=""
              SWinvOn=""
              DiscoveryOn=""
              For Each objService in colServiceList

                     Deb("Action ID: " & objService.InventoryActionID)
                     '*****************************
                     'Trigger HW Inv if appropriate
                     '*****************************
                     if objService.InventoryActionID = "{00000000-0000-0000-0000-000000000001}" Then ' Hardware inventory instance
                            Deb("HW inv instance found .......")
                            Post=Post&",11-01"
                            HWinvOn=objService.LastReportDate
                            yy=Left(HWinvOn,4)
                            mm=mid(HWinvOn,5,2)
                            dd=mid(HWinvOn,7,2)
                            hh=mid(HWinvOn,9,2)
                            mi=mid(HWinvOn,11,2)
                            ss=mid(HWinvOn,13,2)

                            HWinvOn =cdate(MonthName(mm)& " "&dd&","&yy)
                            HWinvOn = DateAdd("h",hh,HWinvOn)
                            HWinvOn = DateAdd("n",mi,HWinvOn)
                            HWinvOn = DateAdd("s",ss,HWinvOn)
                            
                                                      
                            if HWinvOn<dateAdd("d",-1*InvDuration,now) Then ' HW inv was not done in last "InvDuration" days
                                Deb("LastCycleStartedDate = "& objService.LastCycleStartedDate&", LastReportDate = "& objService.LastReportDate & " Check for Schedule Task..")
                                Deb("HW inv was not done in last"&InvDuration&" days. Creating Scheduled Task to run after "&SchFrequency&" hours.")
                                Create_SchTask()
                              	If ScTaskcheck=1 then                                
                                'Trigger it
                                	if Tirgerit("Hardware Inventory",objService.InventoryActionID) = 0  then 
                                    	flag =0
                                    	Post=Post&",11-01F"
                                    	agtConfig =agtConfig &"HW=F,"
						            	'If ReadLog(ccmFolder&"\ccm\logs\InventoryAgent.log" , " errorcode") = 1 or ReadLog(ccmFolder&"\ccm\logs\InventoryAgent.log" , "error ") = 1 Then 'Error found in InventoryAgent.log
							            	'Deb("Error found in InventoryAgent.log")
							            	'Post=Post&",10-02F"
							        	'Else
						            		'Deb("Error not found in InventoryAgent.log")
						            		'Post=Post&",10-02S"
						            	'End If
                                 	Else
                                    	Post=Post&",11-01S"
                                    	'agtConfig =agtConfig &"HW="& FormatDateTime(now,0) &","
                                    	agtConfig =agtConfig &"HW="& USDate(now) &","
                                   		USDate
                                 	End If                                 	
                              	Else
                                 
									Deb("End")
              								Deb("**************************************************************")
              								logFile.Close
									WScript.Quit
                              End If
                            Else
                                Deb("Last HW inv was on "& HWinvOn & " which is newer than "&dateAdd("d",-1*InvDuration,now))
                                Deb(" No need to trigger Hardware inventory. LastCycleStartedDate = "& objService.LastCycleStartedDate&", LastReportDate = "& objService.LastReportDate)
                                agtConfig =agtConfig &"HW="& USDate(HWinvOn) &","
                                Post=Post&",11-01O"
                            End if
                     End if

                     'Deb("Error from previous instance was "&err.number&",   "&err.description&". Checking for SW inv instance.......")
                     '*****************************
                     'Trigger SW Inv if appropriate
                     '*****************************             
                     if objService.InventoryActionID = "{00000000-0000-0000-0000-000000000002}" Then ' Software inventory instance
                            Deb("SW inv instance found .......")
                            Post=Post&",11-02"
                            SWinvOn=objService.LastReportDate
                            yy=Left(SWinvOn,4)
                            mm=mid(SWinvOn,5,2)
                            dd=mid(sWinvOn,7,2)
                            hh=mid(sWinvOn,9,2)
                            mi=mid(sWinvOn,11,2)
                            ss=mid(sWinvOn,13,2)
                            SWinvOn =cdate(MonthName(mm)& " "&dd&","&yy)
                            SWinvOn = DateAdd("h",hh,SWinvOn)
                            SWinvOn = DateAdd("n",mi,SWinvOn)
                            SWinvOn = DateAdd("s",ss,SWinvOn)
                                                                                    
                            if SWinvOn<dateAdd("d",-1*InvDuration,now) then ' SW inv was not done in last "InvDuration" days
                                 Deb("LastCycleStartedDate = "& objService.LastCycleStartedDate&", LastReportDate = "& objService.LastReportDate & " Check for Schedule Task..")
                                  Deb("SW inv was not done in last "&InvDuration&" days. Creating Scheduled Task to run after "&SchFrequency&" hours.")
   								Create_SchTask()
   								If ScTaskcheck=1 then 
                                'Trigger it  Software Inventory Collection
                                if Tirgerit("Software Inventory",objService.InventoryActionID) = 0 Then
                                    flag =0
                                    Post=Post&",11-02F"
                                    agtConfig =agtConfig &"SW=F,"
						            'If ReadLog(ccmFolder&"\ccm\logs\InventoryAgent.log" , " errorcode") = 1 or ReadLog(ccmFolder&"\ccm\logs\InventoryAgent.log" , "error ") = 1 Then 'Error found in InventoryAgent.log
							           ' Deb("Error found in InventoryAgent.log")
							           ' Post=Post&",10-02F"
							        'Else
						            	'Deb("Error not found in InventoryAgent.log")
						            	'Post=Post&",10-02S"
						            'End If
                                Else
                                    Post=Post&",11-02S"
                                    'agtConfig =agtConfig &"SW="& FormatDateTime(now,0) &","
                                    agtConfig =agtConfig &"SW="& USDate(now) &","
                                    
                                End If
                                
                              	Else
                                 
									Deb("End")
              								Deb("**************************************************************")
              								logFile.Close
									WScript.Quit
                              End If
                                
                              Else
                              	  Deb("Last SW inv was on "& SwinvOn & " which is newer than "&dateAdd("d",-1*InvDuration,now))
                                  Deb(" No need to trigger Software inventory. LastCycleStartedDate = "& objService.LastCycleStartedDate&", LastReportDate = "& objService.LastReportDate)
                                  agtConfig =agtConfig &"SW="& USDate(SWinvOn) &","
                                  Post=Post&",11-02O"
                              End if
                     End if
                     
                     '********************************
                     'Trigger Discovery if appropriate
                     '********************************             
                     if objService.InventoryActionID = "{00000000-0000-0000-0000-000000000003}" Then ' Discovery instance
                                                        
                            Deb("Discovery instance found .......")
                            Post=Post&",11-03"
                            DiscoveryOn=objService.LastReportDate
                            yy=Left(DiscoveryOn,4)
                            mm=mid(DiscoveryOn,5,2)
                            dd=mid(DiscoveryOn,7,2)
                            hh=mid(DiscoveryOn,9,2)
                            mi=mid(DiscoveryOn,11,2)
                            ss=mid(DiscoveryOn,13,2)
                            DiscoveryOn =cdate(MonthName(mm)& " "&dd&","&yy)
                            DiscoveryOn = DateAdd("h",hh,DiscoveryOn)
                            DiscoveryOn = DateAdd("n",mi,DiscoveryOn)
                            DiscoveryOn = DateAdd("s",ss,DiscoveryOn)
                                                        
                            if DiscoveryOn<dateAdd("d",-1*InvDuration,now) Then ' Discovery was not done in last "InvDuration" days
                                Deb("LastCycleStartedDate = "& objService.LastCycleStartedDate&", LastReportDate = "& objService.LastReportDate & " Check for Schedule Task..")
                                Deb("Discovery was not done in last "&InvDuration&" days. Creating Scheduled Task to run after "&SchFrequency&" hours.")
                                	Create_SchTask()
                              If ScTaskcheck=1 then 	
                                'Trigger it Discovery Data Collection
                                if Tirgerit("Discovery Data Collection",objService.InventoryActionID) = 0  then 
                                     flag =0
                                     Post=Post&",11-03F"
                                     agtConfig =agtConfig &"DISC=F,"
                                Else
                                    Post=Post&",11-03S"
                                    'agtConfig =agtConfig &"DISC="& FormatDateTime(now,0) &","
                                    agtConfig =agtConfig &"DISC="& USDate(now) &","
                                    
                                End If
                              
                              Else

				Deb("End")
              			Deb("**************************************************************")
              			logFile.Close
				WScript.Quit
                              End If
                                                            
                            Else
                            	Deb("Last Discovery was on "& DiscoveryOn & " which is newer than "&dateAdd("d",-1*InvDuration,now))
                                Deb(" No need to trigger Discovery. LastCycleStartedDate = "& objService.LastCycleStartedDate&", LastReportDate = "& objService.LastReportDate)
                                agtConfig =agtConfig &"DISC="& USDate(DiscoveryOn) &","
                                Post=Post&",11-03O"
                            End if
                     End if

              Next
              
                     '*******************************
                     'Verify WMI Repository if Inventory Trigger fails
                     '*******************************
              		If (inStr(Post,"11-01S") or inStr(Post,"11-02S") or inStr(Post,"11-03S")) Then
              			VerifyWMI 'Verify WMI Repository irrespective of inventory status on machine
              		End If
              		
                     '*******************************
                     'Repair WMI Repository if Inventory Trigger fails
                     '*******************************
                     If (inStr(Post,"11-01S") or inStr(Post,"11-02S") or inStr(Post,"11-03S")) and inStr(Post,"12-01S") Then
                     RepairClient
                     End if
                     
                     	If (inStr(Post,"11-01S") or inStr(Post,"11-02S") or inStr(Post,"11-03S")) and ResetWMIFlag = 1 Then 'Repair WMI
                     		RepairWMI
                     		RepairClient
				       	End if
				       	
				       	
				       	
					 '******************************
					 'Check for Policy from WMI
					 '******************************
						Set objWMIService2 = GetObject("winmgmts:" _
						    & "{impersonationLevel=impersonate}!\\.\root\ccm\policy\machine\requestedconfig")
						
						Set colItems1 = objWMIService2.ExecQuery("select * from ccm_policy_authoritydata2")
						Deb("Checking Policy from WMI.")
						
						For Each objItem1 in colItems1
						    Deb("Name: " & objItem1.Name)
							LastReplyTime = CDate(Mid(objItem1.LastReplyTime, 5, 2) & "/" & Mid(objItem1.LastReplyTime, 7, 2) & "/" & Left(objItem1.LastReplyTime, 4) & " " & Mid (objItem1.LastReplyTime, 9, 2) & ":" & Mid(objItem1.LastReplyTime, 11, 2) & ":" & Mid(objItem1.LastReplyTime, 13, 2))
						    Deb("LastReplyTime: " & LastReplyTime)
						    'LastReplyTime = left(objItem1.LastReplyTime, 8)
						    agtConfig = agtConfig &"LASTPOLICYTIME="& LastReplyTime &","			    
						    Deb("SysDate : "&Now)
						    Difference = Datediff("d",LastReplyTime,now())   'pthomsen on 8/31/2010: flipped parameters so it would be positive
						    Deb("Difference: " & Difference)
                'pthosmen on 8/31/2010 corrected following logic so that if policy too old then scheduled task is created or logic is run (previously it was never running because negative number was always smaller than positive number)
						    'If cint(Difference) < cint(InvDuration) Then
						    If cint(Difference) > cint(InvDuration) Then
'						    	Deb("Policy was last retrieved "&Difference&" days back on " & LastReplyTime)
'						    Else
							Deb("Policy was last retrieved "&Difference&" days back on " & LastReplyTime&". Creating Schedule Task")
							Create_SchTask()
							If SchTaskCheck=1 then
'						    	Deb("Policy was last retrieved "&Difference&" days back on " & LastReplyTime)
						    	Deb("Resetting policy")
						    	Set smsClient = GetObject("winmgmts:" _
						    & "{impersonationLevel=impersonate}!\\.\root\ccm:SMS_Client")
						    	smsClient.ResetPolicy(0)
						    	Deb("Policy reset done")
						    	Deb("Requesting machine policy")
						    	smsClient.RequestMachinePolicy(0)
						    	Deb("Machine policy request done")
							Post=Post & ",12-03"
							else 
							Deb("Policy was last retrieved "&Difference&" days back on " & LastReplyTime&" Creating Schedule Task")
							end If

						    End If
						    Difference=0
						Next
					 
					 '******************************
					 'Get Patch Scan Status
					 '******************************
					 	Deb("Getting Patch Scan Status")
						'Deb("LastError: "& WMIReadReg("HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\Results\Detect\Lasterror"))
						'Deb("LastSuccessTime: "& WMIReadReg("HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\Results\Detect\Lastsuccesstime"))
						LastError = WMIReadReg("HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\Results\Detect\Lasterror")
						Deb("LastError: "&LastError)
						LastSuccessTime2 = WMIReadReg("HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\Results\Detect\Lastsuccesstime")


						LastSuccessTime = (Mid(LastSuccessTime2, 6, 2) & "/" & Mid(LastSuccessTime2, 9, 2) & "/" & Left(LastSuccessTime2,4) & " " & Mid(LastSuccessTime2, 12))			
						
						'If mid(LastSuccessTime2, 6, 1) = "1" Then
						'	LastSuccessTime = left(LastSuccessTime2, 4) & mid(LastSuccessTime2, 6, 2) & mid (LastSuccessTime2, 9, 2)
						'Else
						'	LastSuccessTime = left(LastSuccessTime2, 4) & mid(LastSuccessTime2, 7, 1) & mid (LastSuccessTime2, 9, 2)
						'End If
						Deb("LastSuccessTime: "&LastSuccessTime)
						'SysDate = DatePart("yyyy", Now()) & DatePart("m", Now()) & DatePart("d", Now())
						Deb("SysDate: " &Now)
						'Difference = SysDate - LastSuccessTime
						Difference = Datediff("d",now(),LastSuccessTime)
						Deb("Difference from LastSuccessTime: " & Difference &". Not triggering WSUS scan as there are already 4 scans running daily")
						If Difference > InvDuration Then
						DEb("Scan date is old. Not triggerring WSUS scan as there are already 4 diffrent scan runs daily")
						End If
						agtConfig =agtConfig &"LASTSCANERROR="& LastError &",LASTSUCCESSSCANTIME="& Usdate(LastSuccessTime2) & ","

						'If LastError <> 0 or Difference > InvDuration Then
							'Service_Control "wuauserv","stop"
							'Service_Control "wuauserv","start"
						'End If

              IF HWinvOn="" then 'No instance of this was found
		  Disabledcomp = 1
                  Deb("Forcing Hardware Inventory Collection. It appears that Hardware inventory is disabled or an instance of this component doesnot exist in WMI. One of the reasons for this is, the client is NOT registered yet")
			Create_SchTask()
			If ScTaskcheck=1 then
                  		if  Tirgerit("Hardware Inventory Collection","{00000000-0000-0000-0000-000000000001}") = 0 Then ' failed to trigger them
                      flag =0
                      Post=Post&",11-01F"
                      agtConfig =agtConfig &"HW=F," 
                      Deb("Forcing Hardware Inventory Collection failed")
                      'Deb("Running WMIRepair Function")
                      'RepairWMI
                      'RepairClient
		    Else 
			Post = Post&",11-01S"
		    End if
		End if 	
              End if
              
              if SWinvOn="" Then
		Disabledcomp = 1
                   Deb(" Forcing software Inventory Collection. It appears that Software inventory is disabled or an instance of this component doesnot exist in WMI. One of the reasons for this is, the client is NOT registered yet")
			Create_SchTask()
			If ScTaskcheck=1 then
                   if Tirgerit("Software Inventory Collection","{00000000-0000-0000-0000-000000000002}") = 0 Then ' No instance of this was found and failed to trigger them
                       flag = 0
                       Post=Post&",11-02F"
                       agtConfig =agtConfig &"SW=F,"
                       Deb("Forcing software Inventory Collection failed")
                       'Deb("Running WMIRepair Function")
	                   'RepairWMI
	                   'RepairClient
		    Else 
			Post = Post&",11-02S"
		    End if
		End if
              End if
              
              if DiscoveryOn="" Then
		Disabledcomp = 1
			Create_SchTask()
			If ScTaskcheck=1 then
                 Deb("Forcing Discovery. It appears that Discovery is disabled or an instance of this component doesnot exist in WMI.  One of the reasons for this is, the client is NOT registered yet")
                 IF Tirgerit("Discovery Data Collection","{00000000-0000-0000-0000-000000000003}") = 0 Then ' No instance of this was found and failed to trigger them
                     flag = 0
                     Post=Post&",11-03F"
                     agtConfig =agtConfig &"DISC=F,"  
                     Deb("Forcing Discovery failed" )
                     'Deb("Running WMIRepair Function")
                     'RepairWMI
                     'RepairClient
		    Else 
			Post = Post&",11-03S"
		    End if
		End if
              End if


                   '*******************************
              		If (inStr(Post,"11-01S") or inStr(Post,"11-02S") or inStr(Post,"11-03S")) Then
              			VerifyWMI 'Verify WMI Repository irrespective of inventory status on machine
              		End If
              		
                     '*******************************
                     'Repair WMI Repository if Inventory Trigger fails
                     '*******************************
                     If (inStr(Post,"11-01S") or inStr(Post,"11-02S") or inStr(Post,"11-03S")) and inStr(Post,"12-01S") Then
                     RepairClient
                     End if
                     
                     	If (inStr(Post,"11-01S") or inStr(Post,"11-02S") or inStr(Post,"11-03S")) and ResetWMIFlag = 1 Then 'Repair WMI
                     		RepairWMI
                     		RepairClient
			End if
              
              '***********************
              'Trigger machine policy
              '***********************
              if Tirgerit("Request & Evaluate Machine","{3A88A2F3-0C39-45fa-8959-81F21BF500CE}")  = 1 then 
                    Deb("Triggered Machine policy")
              End if
          End if
      End if
      '******************
      ' check components
      '******************
      'CheckIndicators = CheckComp
       Dim ReturnChkBITS
       ReturnChkBITS = CheckBITS
       CheckIndicators =  flag * Block16 * CheckComp 
       On Error  goto 0
      
End Function ' Function CheckIndicators

Function CheckBITS()
  On Error  resume next
  Dim objWMI1, SysDir1, colFiles
  Deb("Executing Function CheckBITS")
  Dim BVersion, objService1, objWMIService1, colRunningServices1
  CheckBITS = 1
  set objWMI1 = GetObject("winmgmts:\\.\root\cimv2")
  SysDir1 = Replace(SysDir,"\","\\")
  Set colFiles = objWMI1.ExecQuery _
  ("Select * From CIM_Datafile Where Name = '" & SysDir1 & "\\System32\\QMgr.dll'")
  if colFiles.Count > 0 Then ' Even for 64 bit it is in system 32
  
 	'Verify if service is started. If not start it.
  	Set objWMIService1 = GetObject("winmgmts:" _
    & "{impersonationLevel=impersonate}!\\.\root\cimv2")
	Set colRunningServices1 = objWMIService1.ExecQuery _
	    ("Select * from Win32_Service where DisplayName like '%Background Intelligent Transfer Service%'")

	For Each objService1 in colRunningServices1
	
	If objService1.Started = "False" Then
	If objService1.StartMode = "Disabled" Then
			Deb("Changing BITS Service to Automatic.")
			errReturnCode = objService1.Change( , , , , "Manual")
	End If
	
	If objService1.State = "Stopped" Then
		Deb("Starting BITS Service.")
	    	errReturn = objService1.StartService()
	End If
	End If
	Next
		
      Post=Post&",14-01S"
      BVersion = FSO.GetFileVersion(SysDir & "\System32\QMgr.dll")
      BVersion = Replace(BVersion," ","")
      agtConfig =agtConfig &"BITS="&BVersion&","
      Deb("Length of installed version="&len(BVersion) &"  and production version="&len(BITSVersion))
      Deb("Comparing installed version " & BVersion & " with the production version "& BITSVersion &" as per INI")

      BVersion = left(BVersion,3)
      BVersion = Replace(BVersion,".","")
      BVersion = BVersion*1      

      BITSVersion = Left(BITSVersion,3)
      BITSVersion = Replace(BITSVersion," ","")
      BITSVersion = Replace(BITSVersion,".","")
      BITSVersion = BITSVersion*1
      
      IF BVersion < BITSVersion Then 'BITS is older
           Deb("Installed version is older than production version")
           Post=Post&",14-02F"
      Else
           Deb("Installed version is equal or higher than production version")
           Post=Post&",14-02S"      
      End if
   Else ' No bits found
      Post=Post&",14-01F"
      CheckBITS = 0
   End if 
   On error goto 0
  
End Function


Function CheckComp()
    On Error  resume next
    Err.Clear
    Deb("Executing Function CheckComp()")
    CheckComp = 1
    Post=Post&",11-04O"
    Dim objSCCMclient , objComponents , Component
    Set objSCCMclient = CreateObject("CPApplet.CPAppletMgr")
    Set objComponents = objSCCMclient.GetClientComponents
    If err.Number <> 0 Then ' Failed to create the object
        Deb("Failed to create the CPAppletMgr object. Can not check components on this machine at this time.")
        On error goto 0
        Exit Function
    End if
    Post=Post&",11-04O"
    For Each Component In objComponents
    
      if Component.DisplayName = "SMS Software Updates Agent"  Then 
          if  Component.State =1 then
              Post=Post&",11-041S"
              Deb("SMS Software Updates Agent is enabled")
          Else
              Post=Post&",11-041F"
              Deb("SMS Software Updates Agent is not enabled")
              CheckComp = 0              
          End if
      End if

      if Component.DisplayName = "SMS Inventory Agent"  Then 
          if  Component.State =1 then
              Post=Post&",11-042S"
              Deb("SMS Inventory Agent is enabled")              
          Else
              Deb("SMS Inventory Agent is not enabled")
              Post=Post&",11-042F" 
              CheckComp = 0 
          End if
      End if
      
      if Component.DisplayName = "SMS Software Distribution Agent"  Then 
          if  Component.State =1 then
              Post=Post&",11-043S"
              Deb("SMS Software Distribution Agent is enabled")              
          Else
              Deb("SMS Software Distribution Agent is not enabled") 
              Post=Post&",11-043F"
              CheckComp = 0 
          End if
      End if
    Next
    On Error  goto 0
End function

Sub EnableComp(comp) ' Will be done in next version....
    Deb("Executing Sub EnableComp("&comp&")")
End Sub


Function Tirgerit(AgtName,ActID)
     Tirgerit =0
     Deb("Executing Function Tirgerit("&AgtName&","&ActID&")")
     On Error  resume next
      Dim o , oService , oList , oLists , SMSClient , ActionDate
      Set oService = GetObject("winmgmts:{impersonationLevel=impersonate}!\\.\root\ccm\invagt")
      Set oLists = oService.ExecQuery ("Select * from InventoryActionStatus")
      Set o = getObject("winmgmts://./root/ccm")
      set SMSClient = o.Get("SMS_Client")
      if Disabledcomp = 1 then 
	  SMSClient.TriggerSchedule ActID
             Deb("Triggered "&AgtName)
           Tirgerit =1
           Else 
      For Each oList in oLists
             if oList.InventoryActionID = ActID Then 
                    ActionDate =oList.LastReportDate
                    yy=Left(ActionDate,4)
                    mm=mid(ActionDate,5,2)
                    dd=mid(ActionDate,7,2)
                    hh=mid(ActionDate,9,2)
                    mi=mid(ActionDate,11,2)
                    ss=mid(ActionDate,13,2)
                    ActionDate =cdate(MonthName(mm)& " "&dd&","&yy)
                    if ActionDate<dateAdd("d",-1*InvDuration,now) Then 'inv was not done in last 7 days
                       SMSClient.TriggerSchedule ActID
                       Deb("Triggered "&AgtName)
                       Tirgerit =1
                    Else
                       Deb("Failed to trigger "&AgtName)
                    End if
             End if
      Next
    End if
     On Error  goto 0
     Disabledcomp = 0
End Function

Function AssignSite(sc)
     AssignSite =0
     Deb("Executing Function AssignSite("&sc&")")
     On Error  resume next
     Dim o , SMSClient 
     Set smsclient = CreateObject("Microsoft.SMS.Client")
     smsclient.SetAssignedSite(sc)

     On Error  goto 0
End Function


Function Block16
      Dim MP , SubNet
      Deb("Executing Function Block16")
      MP=""
      SubNet=""

      Block16 =1
      Post=Post&",16-01"
      On Error  resume next
      err.clear

      ASiteCode = ReadReg(RegPath &"\Mobile Client\AssignedSiteCode")
      GPOSiteCode=ReadReg(RegPath &"\Mobile Client\GPRequestedSiteAssignmentCode")
      
      ASiteCode=Replace(ASiteCode," ","")
      GPOSiteCode=Replace(GPOSiteCode," ","")
      
      if GPOSiteCode <>"" and ASiteCode <>"" then ' Both are empty
          Deb("Both Site codes are in the registry. So do nothing")
          'AssignSite(SiteCode)
      Elseif GPOSiteCode <>"" and ASiteCode ="" then ' Both are empty
          Deb("Assigned Site codes missing in the registry. So assigning to GPO sitecode")
          AssignSite(GPOSiteCode)
      Elseif GPOSiteCode = "" and ASiteCode <>"" then '  Then GPO Requested site code is empty
          Deb("GPO Site code is missing in Registry but assigned sitecode exists, Do nothing")
'          AssignSite(SiteCode)
     Else ' Then only Assigned site code is null
         Deb("Both, GPO and Assigned site codes are missing in Registry, Do nothing")
'         AssignSite(GPOSiteCode)
      End if

      
      agtConfig =agtConfig &"SC="&ReadReg(RegPath &"\Mobile Client\AssignedSiteCode")&","
      agtConfig =agtConfig &"GPSC="&ReadReg(RegPath &"\Mobile Client\GPRequestedSiteAssignmentCode")&","

      if err.number = 0 then 
          Post=Post&",16-02S"
          Deb("Successfully read site codes from Registry. Assigned Site Code=" &ASiteCode&" and GPO Requested site code ="&GPOSiteCode&" This means whatever in the registry, including a null value, was read correctly" )
      Else
          Post=Post&",16-02F"
      End if
      
      Set objWMIService = GetObject("winmgmts:{impersonationLevel=impersonate}!\\.\root\ccm\SoftMgmtAgent")
      Set colServiceList = objWMIService.ExecQuery ("Select * from CCM_SourceUpdateHistory")
      For Each objService in colServiceList
          MP= objService.LastAssignedMP 
          SubNet = Replace(objService.LastSubnets,";","")
      Next



      if err.number <> 0 or MP ="" or SubNet = "" then ' There was a problem collecting this data
          Deb("There was a problem collecting MP/Subnet data. MP="&MP&" and SubNet ="&SubNet)
          Post=Post&",16-03F"
          'Commented below line by kjayavel on 08/20 to avoid client un-installation
	  'Block16 =0
      Else
          Post=Post&",16-03S"
          Deb("Collected MP and Subnet details from WMI")
      End if

      agtConfig =agtConfig & "MP="&MP&","
      agtConfig =agtConfig & "SNET="&SubNet &","
      On Error  goto 0
End Function
 
Function GetSiteCode(Domain)
    On Error  resume next
    Deb("Executing Function GetSiteCode("&Domain&")")
    Domain=UCASE(Domain)
    select case Domain
          CASE "FAREAST.CORP.MICROSOFT.COM"
          GetSiteCode = "AUA"
          CASE "SOUTHPACIFIC.CORP.MICROSOFT.COM"
          GetSiteCode = "AUA"
          CASE "AFRICA.CORP.MICROSOFT.COM"
          GetSiteCode = "EMA"
          CASE "EUROPE.CORP.MICROSOFT.COM"
          GetSiteCode = "EMA"
          CASE "MIDDLEEAST.CORP.MICROSOFT.COM"
          GetSiteCode = "EMA"
          CASE "NORTHAMERICA.CORP.MICROSOFT.COM"
          GetSiteCode = "NAM"
          CASE "SOUTHAMERICA.CORP.MICROSOFT.COM"
          GetSiteCode = "NAM"
          CASE "REDMOND.CORP.MICROSOFT.COM"
          GetSiteCode = "PUG"
          CASE Else
          GetSiteCode = "AUTO"          
    End Select
    On Error  goto 0
End Function

Function Check4RecentInstall()
      'This function will return 0 if no client installation was success in last 4 hours. Reading ccmsetup.log for verification.
      Check4RecentInstall =0
      Deb("Executing Function Check4RecentInstall() to read ccmsetup.log for recent install")
      On Error  resume next
      inDate=""
      IF FSO.FileExists(ccmSetupFldr&"\CcmSetup\CCMSetup.Log") Then 
           Dim c4iFSO , lineRead , inTime
           SET c4iFSO = FSO.OpenTextFile(ccmSetupFldr&"\CcmSetup\CCMSetup.Log",1)
           Do while c4iFSO.AtEndOfStream <> True 
               lineRead = c4iFSO.ReadLine
               'if instr(lineRead,"Successfully deleted the ccmsetup service") Then '
		'Added below line by kjayavel on 08/19 to use the right string for checking client installation
		if instr(lineRead,"Sending Fallback Status Point message, STATEID='400'.") Then
                    inDate = lineRead 
               End if
           Loop
           if Len(inDate) > 3 then ' there was some value
              inDate = split(inDate,"component")(0)
              inTime = split(inDate,"date=")(0)
              inTime = split(inTime ,"time=")(1)
              inTime = Replace(inTime,"""","")
              inTime = split(inTime,".")(0)
              inDate = split(inDate,"date=")(1)
              inDate =Replace(inDate,"""","")
              inDate =Replace(inDate," ","")
              inDate = inDate &" "& inTime
              Deb("last install date : "&inDate)
              inDate = Cdate(inDate)
              Deb("Last client installation as per ccmsetup.log was at " & inDate)
              'Deb(inDate & " and the difference with current time "& now &"  is "& Abs(DateDiff("n",inDate,now()))&" minute(s)" )
              if Abs(DateDiff("n",inDate,now())) < 240 then ' Recent install found
                  Check4RecentInstall =1
                  Deb("Recent install found")
              End if
           End if
      Else
           Deb(ccmSetupFldr&"\CcmSetup\CCMSetup.Log was not found")
      End if
      On Error  goto 0                   
End Function

Function USDate(dt)
  On Error resume next
  yy=Year(dt)
  mm=Month(dt)
  dd=Day(dt)
  hh=Hour(dt)
  mi=Minute(dt)
  ss=Second(dt)
  USDate = mm&"/"&dd&"/"&yy&" "& hh &":"&mi&":"&ss
  On Error goto 0
End Function

Sub VerifyWMI()
	On Error Resume Next
	Dim VerifyWMIResultFile, VerifyWMIResultLine, ResetWMIResultFile, ResetWMIResultLine
	Deb("Executing Function VerifyWMI()")
	if osversion >= 6 then 
	WSH.Run("cmd /C winmgmt.exe /verifyrepository > " & windir & "\Temp\VerifyWMIResult.txt"), 0, True
	If fso.FileExists(windir & "\Temp\VerifyWMIResult.txt") Then 
		Set VerifyWMIResultFile = FSO.OpenTextFile(windir & "\Temp\VerifyWMIResult.txt", 1)
			VerifyWMIResultLine = left(lcase(VerifyWMIResultFile.ReadAll), 28)
			If VerifyWMIResultLine = "wmi repository is consistent" Then
				Post=Post&",12-01S"
				Deb("WMI repository is consistent")				
			Else
				Deb("WMI repository is not consistent.")
				Post=Post&",12-01F"
				ResetWMIFlag = 1
			End If
	Else
		Deb("Unable to run winmgmt.exe /verifyrepository")		
    End If
    Else    
	    Deb ("Running XP command rundll32 wbemupgd, UpgradeRepository")
		WSH.Run("cmd /C rundll32 wbemupgd, UpgradeRepository > " & windir & "\Temp\VerifyWMIResult.txt"), 0, True
    End If 
    On Error goto 0
End Sub

Sub Service_Control(sname,purpose)
	Dim err_return
	Set objWMIService = GetObject("winmgmts:{impersonationLevel=impersonate}!\\.\root\cimv2")
	Set colListOfServices = objWMIService.ExecQuery("Select * from Win32_Service where Name = '" & sname & "'")
	For Each objService In colListOfServices
		If objService.name = sname Then
			If purpose = "stop" Then
				err_return = objService.stopservice
				If err_return = 3 Then
					Set colServiceList2 = objWMIService.ExecQuery("Associators of {Win32_Service.Name='" & objService.name & "'} Where AssocClass=Win32_DependentService " & "Role=Antecedent" )
					For Each objService2 in colServiceList2
						objService2.StopService()
						Deb("Dependent Service: " & objService2.Displayname & " is stopped")
					Next
				End If
				objService.StopService()
				Deb("Service: " & objService.Displayname & " is stopped")
			End If
			
			If purpose = "start" Then
				err_return = objService.stopservice
				If NOT err_return = 10 Then
					Set colServiceList2 = objWMIService.ExecQuery("Associators of {Win32_Service.Name='" & objService.name & "'} Where AssocClass=Win32_DependentService " & "Role=Antecedent" )
					For Each objService2 in colServiceList2
						objService2.StartService()
						Deb("Dependent Service " & objService2.Displayname & " is started")
					Next
				End If
				objService.StartService()
				Deb("Service: " & objService.Displayname & " is started")
			End If
		End If
	Next
End Sub

Function Create_SchTask()

	Dim current, oShell, Time20, finaltime, WshShell, MyFile, schedule, SchTaskCreatedOn, return1, SCDifference,ScheduledTime
	deb("Running Create_SchTask()")
	ScTaskcheck=0
	current = now() 
		set oShell = CreateObject("WScript.Shell") 
		Time20 = DateAdd("h",SchFrequency,current)
		finaltime = Formatdatetime(Time20,vbshortTime)
		finaltime = finaltime&":00"
		deb("Scheduled task will be set to run at : " & finaltime)
	  
	Set WshShell = WScript.CreateObject("WScript.Shell")
	If OSversion<6 then            
		CH = """CH"""
		Command = "cmd /C SCHTASKS /Query | find "&CH&" > " & windir & "\Temp\VerifySchTask.txt"
		WshShell.Run(command), 0, True
	Else
		WshShell.Run("cmd /C SCHTASKS /Query /FO CSV /TN CH > " & windir & "\Temp\VerifySchTask.txt"), 0, True
	end If

	Set MyFile = fso.OpenTextFile(windir & "\Temp\VerifySchTask.txt", 1)
	If MyFile.AtEndOfStream Then
		'schedule = "cmd /C SCHTASKS /Create /SC once /TN CH /TR ""\\"&logondomain&"\netlogon\sms\msch\msch.bat"" /ST " & finaltime & " /RU SYSTEM /F"
		If OSversion >=6 then
			schedule = "cmd /C SCHTASKS /Create /SC once /TN CH /TR "&strPath&"msch.bat /ST " & finaltime & " /RU SYSTEM /F"
		Else 
			schedule = "cmd /C SCHTASKS /Create /SC once /TN CH /TR "&strPath&"msch.bat /ST " & finaltime & " /RU SYSTEM"
		End if 
		deb(schedule)
		return1 = WshShell.Run(schedule, 0, True)
			If return1 = 0 Then
				WriteReg RegPath &"\CH\SchTaskCreatedOn", Now, "REG_SZ"
				deb("The scheduled task CH.job was successfully created")
				Deb("End")
				Deb("**************************************************************")
				logFile.Close
			Else              
				deb("There were problems creating the scheduled task CH.job")
			End If 
		ScTaskcheck=0 'Task created?
	Else
		deb("Scheduled Task already exists.")
		SchTaskCreatedOn=ReadReg(RegPath &"\CH\SchTaskCreatedOn")
		deb("Scheduled Task was created on: " & SchTaskCreatedOn)
		ScheduledTime=DateAdd("h",SchFrequency,SchTaskCreatedOn)	
		'SCDifference = DateDiff("h",SchTaskCreatedOn, Now())		
		SCDifference = DateDiff("n",ScheduledTime, Now())
		deb("Time difference between already existing scheduled task and current time : " & SCDifference)

		'deb("SchFrequency in hours: " & SchFrequency)

		'If clng(SCDifference) = clng(SchFrequency) then
		deb (clng(scdifference))
		If clng(SCDifference) >= 0 and clng(SCDifference) < 3 then

				WshShell.Run("cmd /C SCHTASKS /Delete /TN CH /F"), 0, True
				deb("Deleted Scheduled Task CH.job")
				ScTaskcheck=1 'Task Deleted
				DeleteReg(RegPath &"\CH\SchTaskCreatedOn")
				Exit Function		
		'Else if	clng(SCDifference) > clng(SchFrequency)then					
		Else if	clng(SCDifference) > 0 then
				deb("Since previous Schedule task did not run Creating new schedule task")	
				WshShell.Run("cmd /C SCHTASKS /Delete /TN CH /F"), 0, True
				deb("Deleted Scheduled Task CH.job")
				If Osversion >=6 then
				schedule = "cmd /C SCHTASKS /Create /SC once /TN CH /TR "&strPath&"msch.bat /ST " & finaltime & " /RU SYSTEM /F"
				Else
				schedule = "cmd /C SCHTASKS /Create /SC once /TN CH /TR "&strPath&"msch.bat /ST " & finaltime & " /RU SYSTEM"
				End if
						deb(schedule)
						return1 = WshShell.Run(schedule, 0, True)
					If return1 = 0 Then
						WriteReg RegPath &"\CH\SchTaskCreatedOn", Now, "REG_SZ"
						deb("The scheduled task CH.job was successfully created")
						'Deb("End")
						 'Deb("**************************************************************")
						'logFile.Close
					Else              
						 deb("There were problems creating the scheduled task CH.job")
					End If 
					ScTaskcheck=0
		Else
				ScTaskcheck=0
				Deb("The existing schedule task is recently created on "& SchTaskCreatedOn &" hours")  
				deb("Skipping recreating scheduled task")

			End If
			End if
	End If  
End Function

Function RepairClient()
		Deb("Repairing CCM Client.")
		Err.Clear
		Set objWMIService = GetObject("winmgmts:{impersonationLevel=impersonate}!\\.\root\ccm")
	    Set ResettingClient = objWMIService.Get("SMS_Client")
	    ResettingClient.RepairClient
	    'On error Resume next	      								  
	    If Err.number <> 0 then
	    Deb("Client repair Failed Uninstalling the CCM Client.")	
	    	If DeInstall("12") = 1 then
        		if Install("12") = 1 then
        			InstalledOnce=True
         		Else
        			CopyLogs=True
        		End if 
        	Else
        		CopyLogs=True
        	End if
        	err.Clear
        Else
			err.Clear
			Deb("CCM Client Repair Succeeded.")	  
		Exit Function	      								  		  
	    End If
End Function

Function RepairWMI()
	Service_Control "Winmgmt","stop"
	Deb("Resetting WMI Repository.")
	WSH.Run("cmd /C winmgmt.exe /salvagerepository > " & windir & "\Temp\ResetWMIResult.txt"), 0, True
	Service_Control "Winmgmt","start"
	If fso.FileExists(windir & "\Temp\ResetWMIResult.txt") Then
	Set ResetWMIResultFile = FSO.OpenTextFile (windir & "\Temp\ResetWMIResult.txt", 1)
	Do while ResetWMIResultFile.AtEndOFStream <> True
			ResetWMIResultLine = left(lcase(ResetWMIResultFile.ReadLine), 28)
			If ResetWMIResultLine <> "wmi repository is consistent" Then
			Deb("WMI repository reset failed.")
			Post=Post&",12-02F"
			End If
	Loop
	End If
	If inStr(Post,"12-02F") Then 'Check for WMI Reset Success
	Else
	Deb("WMI repository reset successfull.")
	Post=Post&",12-02S"
	End if
		
End Function
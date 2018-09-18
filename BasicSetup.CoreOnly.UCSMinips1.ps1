<#
.NOTES
Copyright (c) 2018 Cisco and/or its affiliates.
This software is licensed to you under the terms of the Cisco Sample
Code License, Version 1.0 (the "License"). You may obtain a copy of the
License at
               https://developer.cisco.com/docs/licenses
All use of the material herein must be in accordance with the terms of
the License. All rights not expressly granted by the License are
reserved. Unless required by applicable law or agreed to separately in
writing, software distributed under the License is distributed on an "AS
IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express
or implied.
#>
############################################################################################################
# This is an example script. It is not intended to be run in your environment without modification.
# This script exits by default to prevent damage to your existing environment. You should not run it
# Unless you fully understand it and have modified it properly to work in your enviroment. 
# Do not remove the "exit" line from this script. Select your intended lines and run them individually or 
# in small groups.
############################################################################################################
exit
############################################################################################################
# Note
# Change below IP addressing before using this script.
############################################################################################################
$ucsMgmtIP="1.1.1.1"
$ucsNTP = "1.1.1.2"

#These names are for VLANS.
$ManagementVLANName = "Mgmt"
$vMotionVLANName    = "LM"
$StorageVLANName    = "Storage"
$VMVLANName         = "VM"

#The site name is used to seperate configurations in UCS. We are assuming one site per cluster.
$SiteName = "VMWARE-C1" 

#Connect to UCS to to configure.

Import-Module Cisco.UCSManager
connect-ucs $ucsMgmtIP


#Turn off Call Home Reporting
Get-UcsCallhomeAnonymousReporting | Set-UcsManagedObject -PropertyMap @{AdminState="off"; UserAcknowledged="yes"; } -force

#Set Jumbo Frames System Policy
Start-UcsTransaction
$mo = Get-UcsQosclassDefinition | Set-UcsQosclassDefinition -Descr "" -PolicyOwner "local" -Force
$mo_1 = Get-UcsBestEffortQosClass | Set-UcsBestEffortQosClass -Mtu "9216" -MulticastOptimize "no" -Name "" -Weight "5" -force
Complete-UcsTransaction

#Set the time server and Time Zone
Start-UcsTransaction
$mo = Get-UcsSvcEp | Get-UcsTimezone | Set-UcsTimezone -AdminState "enabled" -Descr "" -PolicyOwner "local" -Port 0 -Timezone "America/Detroit (Eastern Time - Michigan - most locations)" -Force
$mo_1 = Get-UcsSvcEp | Get-UcsTimezone | add-UcsNtpServer -Name $ucsNTP 
Complete-UcsTransaction


#Get ports in the fabric that have a module installed
Get-UcsFabricPort | sort switchID,portid | ?{$_.XcvrType -notmatch "unknown"}|ft adminstate,xcvrType,status,switchID,portid, slotID

#Enable uplinks
Add-UcsUplinkPort -FiLanCloud A -portid 1 -slot 1
Add-UcsUplinkPort -FiLanCloud B -portId 1 -slot 1
Add-UcsUplinkPort -FiLanCloud A -portid 2 -slot 1
Add-UcsUplinkPort -FiLanCloud B -portId 2 -slot 1

#Configure Port Channel
$PortChannelA = Get-UcsFiLanCloud -Id A | Add-UcsUplinkPortChannel -Name NEXUS-LAN-A -PortId 10 -AdminState enabled
$portChannelA | Add-UcsUplinkPortChannelMember -PortId 1 -SlotId 1
$portChannelA | Add-UcsUplinkPortChannelMember -PortId 2 -SlotId 1
$PortChannelB = Get-UcsFiLanCloud -Id B | Add-UcsUplinkPortChannel -Name NEXUS-LAN-B -PortId 11 -AdminState enabled
$portChannelB | Add-UcsUplinkPortChannelMember -PortId 1 -SlotId 1
$portChannelB | Add-UcsUplinkPortChannelMember -PortId 2 -SlotId 1


#Create VLANS
#You can change the numbers below, but the names must be changed at the top of the script.
#These VLAN names are mapped to vNIC templates later is this script.
 
Get-UcsLanCloud | Add-UcsVlan -CompressionType "included" -DefaultNet "no" -Id 50 -McastPolicyName "" -Name $ManagementVLANName -PolicyOwner "local" -PubNwName "" -Sharing "none"
Get-UcsLanCloud | Add-UcsVlan -CompressionType "included" -DefaultNet "no" -Id 60 -McastPolicyName "" -Name $vMotionVLANName    -PolicyOwner "local" -PubNwName "" -Sharing "none"
Get-UcsLanCloud | Add-UcsVlan -CompressionType "included" -DefaultNet "no" -Id 70 -McastPolicyName "" -Name $StorageVLANName    -PolicyOwner "local" -PubNwName "" -Sharing "none"
Get-UcsLanCloud | Add-UcsVlan -CompressionType "included" -DefaultNet "no" -Id 80 -McastPolicyName "" -Name $vMVLANName         -PolicyOwner "local" -PubNwName "" -Sharing "none"

#Create Site Name.
add-UcsOrg -Name $SiteName


############################################################################################################
# Critical Note
# Do not duplicate MAC addresses in your L2 space. The below MAC pool is provided only as an example
############################################################################################################

#Create MAC Address Pools
Start-UcsTransaction
$mo = Get-UcsOrg -Name $SiteName | Add-UcsMacPool -AssignmentOrder "sequential" -Descr "VMWare MAC Pool" -Name "VMWare1" -PolicyOwner "local"
$mo_1 = $mo | Add-UcsMacMemberBlock -From "00:25:B5:01:00:00" -To "00:25:B5:01:00:FF"
Complete-UcsTransaction

#Create UUIDs for Servers
Start-UcsTransaction
$mo = Get-UcsOrg -Name $SiteName  | Add-UcsUuidSuffixPool -AssignmentOrder sequential -Descr "" -Name "VMWare" -PolicyOwner "local" -Prefix "derived"
$mo_1 = $mo | Add-UcsUuidSuffixBlock -From "1000-000000000001" -To "1000-000000000010"
Complete-UcsTransaction

#Assign management IP pool for four servers.
Get-UcsOrg -Level root | Get-UcsIpPool -Name "ext-mgmt" -LimitScope | Add-UcsIpPoolBlock -DefGw "192.168.100.1" -From "192.168.100.16" -To "192.168.100.19"

#Create VNIC Templates

Start-UcsTransaction
$mo = Get-UcsOrg -Name $SiteName  | Add-UcsVnicTemplate -Descr "" -IdentPoolName "VMWare1" -Mtu 1500 -Name "eth0-MgmtA" -NwCtrlPolicyName "" -PinToGroupName "" -PolicyOwner "local" -QosPolicyName "" -StatsPolicyName "default" -SwitchId "A" -TemplType 'updating-template'
$mo_1 = $mo | Add-UcsVnicInterface -ModifyPresent -DefaultNet "no" -Name $ManagementVLANName
Complete-UcsTransaction

Start-UcsTransaction
$mo = Get-UcsOrg -Name $SiteName  | Add-UcsVnicTemplate -Descr "" -IdentPoolName "VMWare1" -Mtu 1500 -Name "eth1-MgmtB" -NwCtrlPolicyName "" -PinToGroupName "" -PolicyOwner "local" -QosPolicyName "" -StatsPolicyName "default" -SwitchId "B" -TemplType 'updating-template'
$mo_1 = $mo | Add-UcsVnicInterface -ModifyPresent -DefaultNet "no" -Name $ManagementVLANName
Complete-UcsTransaction

Start-UcsTransaction
$mo = Get-UcsOrg -Name $SiteName  | Add-UcsVnicTemplate -Descr "" -IdentPoolName "VMWare1" -Mtu 1500 -Name "eth2-LM_A" -NwCtrlPolicyName "" -PinToGroupName "" -PolicyOwner "local" -QosPolicyName "" -StatsPolicyName "default" -SwitchId "A" -TemplType 'updating-template'
$mo_1 = $mo | Add-UcsVnicInterface -ModifyPresent -DefaultNet "no" -Name $vMotionVLANName
Complete-UcsTransaction

Start-UcsTransaction
$mo = Get-UcsOrg -Name $SiteName  | Add-UcsVnicTemplate -Descr "" -IdentPoolName "VMWare1" -Mtu 1500 -Name "eth3-LM_B" -NwCtrlPolicyName "" -PinToGroupName "" -PolicyOwner "local" -QosPolicyName "" -StatsPolicyName "default" -SwitchId "B" -TemplType 'updating-template'
$mo_1 = $mo | Add-UcsVnicInterface -ModifyPresent -DefaultNet "no" -Name $vMotionVLANName
Complete-UcsTransaction

Start-UcsTransaction
$mo = Get-UcsOrg -Name $SiteName  | Add-UcsVnicTemplate -Descr "" -IdentPoolName "VMWare1" -Mtu 1500 -Name "eth4-Storage_A" -NwCtrlPolicyName "" -PinToGroupName "" -PolicyOwner "local" -QosPolicyName "" -StatsPolicyName "default" -SwitchId "A" -TemplType 'updating-template'
$mo_1 = $mo | Add-UcsVnicInterface -ModifyPresent -DefaultNet "yes" -Name $StorageVLANName
Complete-UcsTransaction

Start-UcsTransaction
$mo = Get-UcsOrg -Name $SiteName  | Add-UcsVnicTemplate -Descr "" -IdentPoolName "VMWare1" -Mtu 1500 -Name "eth5-Storage_B" -NwCtrlPolicyName "" -PinToGroupName "" -PolicyOwner "local" -QosPolicyName "" -StatsPolicyName "default" -SwitchId "B" -TemplType 'updating-template'
$mo_1 = $mo | Add-UcsVnicInterface -ModifyPresent -DefaultNet "yes" -Name $StorageVLANName
Complete-UcsTransaction

Start-UcsTransaction
$mo = Get-UcsOrg -Name $SiteName  | Add-UcsVnicTemplate -Descr "" -IdentPoolName "VMWare1" -Mtu 1500 -Name "eth6-VM_A" -NwCtrlPolicyName "" -PinToGroupName "" -PolicyOwner "local" -QosPolicyName "" -StatsPolicyName "default" -SwitchId "A" -TemplType 'updating-template'
$mo_1 = $mo | Add-UcsVnicInterface -ModifyPresent -DefaultNet "no" -Name $VMVLANName
Complete-UcsTransaction

Start-UcsTransaction
$mo = Get-UcsOrg -Name $SiteName  | Add-UcsVnicTemplate -Descr "" -IdentPoolName "VMWare1" -Mtu 1500 -Name "eth7-VM_B" -NwCtrlPolicyName "" -PinToGroupName "" -PolicyOwner "local" -QosPolicyName "" -StatsPolicyName "default" -SwitchId "B" -TemplType 'updating-template'
$mo_1 = $mo | Add-UcsVnicInterface -ModifyPresent -DefaultNet "no" -Name $VMVLANName
Complete-UcsTransaction

#Require User Acknowledgement for changes.
Get-UcsOrg -Name $SiteName  | Add-UcsMaintenancePolicy -Descr "" -Name "UserAck" -PolicyOwner "local" -SchedName "" -UptimeDisr "user-ack"

#Local Disk Mirrored Policy
#NOT NEEDED FOR ISCSI BOOT>>>>
Get-UcsOrg -Name $SiteName  | Add-UcsLocalDiskConfigPolicy -Descr "" -FlexFlashRAIDReportingState "disable" -FlexFlashState "disable" -Mode "raid-mirrored" -Name "Raid1Mirrored" -PolicyOwner "local" -ProtectConfig "yes"

#BIOS Settings
Start-UcsTransaction
$mo = Get-UcsOrg -Name $SiteName  | Add-UcsBiosPolicy -Descr "" -Name "ESXi_B200M5" -PolicyOwner "local" -RebootOnUpdate "no"
$mo_1 = $mo | Set-UcsBiosVfAltitude -VpAltitude "platform-default"
$mo_2 = $mo | Set-UcsBiosVfCPUPerformance -VpCPUPerformance enterprise
$mo_5 = $mo | Set-UcsBiosVfDRAMClockThrottling -VpDRAMClockThrottling performance
$mo_6 = $mo | Set-UcsBiosVfDirectCacheAccess -VpDirectCacheAccess enabled
$mo_8 = $mo | Set-UcsBiosEnhancedIntelSpeedStep -VpEnhancedIntelSpeedStepTech enabled
$mo_9 = $mo | Set-UcsBiosExecuteDisabledBit -VpExecuteDisableBit "enabled"
$mo_10 = $mo | Set-UcsBiosVfFrequencyFloorOverride -VpFrequencyFloorOverride enabled
$mo_12 = $mo | Set-UcsBiosHyperThreading -VpIntelHyperThreadingTech "enabled"
$mo_13 = $mo | Set-UcsBiosTurboBoost -VpIntelTurboBoostTech enabled
$mo_14 = $mo | Set-UcsBiosIntelDirectedIO -VpIntelVTForDirectedIO enabled
$mo_15 = $mo | Set-UcsBiosVfIntelVirtualizationTechnology -VpIntelVirtualizationTechnology "enabled"
$mo_18 = $mo | Set-UcsBiosLvDdrMode -VpLvDDRMode performance-mode
$mo_24 = $mo | Set-UcsBiosVfProcessorCState -VpProcessorCState disabled
$mo_25 = $mo | Set-UcsBiosVfProcessorC1E -VpProcessorC1E disabled
$mo_26 = $mo | Set-UcsBiosVfProcessorC3Report -VpProcessorC3Report disabled
$mo_27 = $mo | Set-UcsBiosVfProcessorC6Report -VpProcessorC6Report disabled
$mo_28 = $mo | Set-UcsBiosVfProcessorC7Report -VpProcessorC7Report disabled
$mo_29 = $mo | Set-UcsBiosVfProcessorEnergyConfiguration -VpEnergyPerformance performance -VpPowerTechnology performance
$mo_34 = $mo | Set-UcsBiosVfSelectMemoryRASConfiguration -VpSelectMemoryRASConfiguration maximum-performance
Complete-UcsTransaction -force

#Create Policy to set encryption on KVM connections
Get-UcsOrg -Name $SiteName | Add-UcsComputeKvmMgmtPolicy -Descr "" -Name "Encrypted" -PolicyOwner "local" -VmediaEncryption "enable"

#Firmware Policies
#Pay attention to the firmware bundle. It needs to match what you have loaded.
Get-UcsOrg -Name $SiteName  | Add-UcsFirmwareComputeHostPack -BladeBundleVersion "4.0(1a)B" -Descr "" -IgnoreCompCheck "yes" -Mode "staged" -Name "VMWare-Cluster1" -OverrideDefaultExclusion "yes" -PolicyOwner "local" -RackBundleVersion "" -StageSize 0 -UpdateTrigger "immediate"

#Create Service Profile Template
Start-UcsTransaction
$mo = Get-UcsOrg -Name $SiteName -LimitScope | Add-UcsServiceProfile -BootPolicyName "default" -HostFwPolicyName "VMWare-Cluster1" -IdentPoolName "VMWare" -KvmMgmtPolicyName "Encrypted" -LocalDiskPolicyName "Raid1Mirrored" -MaintPolicyName "UserAck" -BiosProfileName "ESXi_B200M5" -Name "VMWare-Cluster1" -Type "updating-template"
$mo_1 = $mo | Add-UcsVnicFcNode -ModifyPresent -Addr "pool-derived" -IdentPoolName "node-default"
$mo_2 = $mo | Add-UcsVnic -AdaptorProfileName "VMWare" -AdminVcon "1" -Name "eth0-MgmtA"      -NwTemplName "eth0-MgmtA"     -Order "1" -SwitchId "A"
$mo_3 = $mo | Add-UcsVnic -AdaptorProfileName "VMWare" -AdminVcon "1" -Name "eth1-MgmtB"      -NwTemplName "eth1-MgmtB"     -Order "2" -SwitchId "B"
$mo_4 = $mo | Add-UcsVnic -AdaptorProfileName "VMWare" -AdminVcon "1" -Name "eth2-LM_A"       -NwTemplName "eth2-LM_A"      -Order "3" -SwitchId "A"
$mo_5 = $mo | Add-UcsVnic -AdaptorProfileName "VMWare" -AdminVcon "1" -Name "eth3-LM_B"       -NwTemplName "eth3-LM_B"      -Order "4" -SwitchId "B"
$mo_6 = $mo | Add-UcsVnic -AdaptorProfileName "VMWare" -AdminVcon "1" -Name "eth4-Strorage_A" -NwTemplName "eth4-Storage_A" -Order "5" -SwitchId "A"
$mo_7 = $mo | Add-UcsVnic -AdaptorProfileName "VMWare" -AdminVcon "1" -Name "eth5-Storage_B"  -NwTemplName "eth5-Storage_B" -Order "6" -SwitchId "B"
$mo_8 = $mo | Add-UcsVnic -AdaptorProfileName "VMWare" -AdminVcon "1" -Name "eth6-VM_A"       -NwTemplName "eth6-VM_A"      -Order "7" -SwitchId "A"
$mo_9 = $mo | Add-UcsVnic -AdaptorProfileName "VMWare" -AdminVcon "1" -Name "eth7-VM_B"       -NwTemplName "eth7-VM_B"      -Order "8" -SwitchId "B"
$mo_10 = $mo | Add-UcsVnicDefBeh -ModifyPresent -Action "none" -Descr "" -Name ""             -NwTemplName "" -PolicyOwner "local" -Type "vhba"
$mo_11 = $mo | Add-UcsFabricVCon -ModifyPresent -Fabric "NONE" -Id "1" -InstType "manual" -Placement "physical" -Select "all" -Share "shared" -Transport "ethernet","fc"
$mo_12 = $mo | Add-UcsFabricVCon -ModifyPresent -Fabric "NONE" -Id "2" -InstType "manual" -Placement "physical" -Select "all" -Share "shared" -Transport "ethernet","fc"
$mo_13 = $mo | Add-UcsFabricVCon -ModifyPresent -Fabric "NONE" -Id "3" -InstType "manual" -Placement "physical" -Select "all" -Share "shared" -Transport "ethernet","fc"
$mo_14 = $mo | Add-UcsFabricVCon -ModifyPresent -Fabric "NONE" -Id "4" -InstType "manual" -Placement "physical" -Select "all" -Share "shared" -Transport "ethernet","fc"
$mo_15 = $mo | Set-UcsServerPower -State "admin-up"
Complete-UcsTransaction

#Create a service profile
Get-UcsOrg -Name $SiteName | Get-UcsServiceProfile -Name "VMWare-Cluster1" -LimitScope | Add-UcsServiceProfileFromTemplate -NewName @("VMW-C1-N1") -DestinationOrg $SiteName
Get-UcsOrg -Name $SiteName | Get-UcsServiceProfile -Name "VMWare-Cluster1" -LimitScope | Add-UcsServiceProfileFromTemplate -NewName @("VMW-C1-N2") -DestinationOrg $SiteName
Get-UcsOrg -Name $SiteName | Get-UcsServiceProfile -Name "VMWare-Cluster1" -LimitScope | Add-UcsServiceProfileFromTemplate -NewName @("VMW-C1-N3") -DestinationOrg $SiteName
Get-UcsOrg -Name $SiteName | Get-UcsServiceProfile -Name "VMWare-Cluster1" -LimitScope | Add-UcsServiceProfileFromTemplate -NewName @("VMW-C1-N4") -DestinationOrg $SiteName
Get-UcsOrg -Name $SiteName | Get-UcsServiceProfile -Name "VMWare-Cluster1" -LimitScope | Add-UcsServiceProfileFromTemplate -NewName @("VMW-C1-N5") -DestinationOrg $SiteName
Get-UcsOrg -Name $SiteName | Get-UcsServiceProfile -Name "VMWare-Cluster1" -LimitScope | Add-UcsServiceProfileFromTemplate -NewName @("VMW-C1-N6") -DestinationOrg $SiteName
Get-UcsOrg -Name $SiteName | Get-UcsServiceProfile -Name "VMWare-Cluster1" -LimitScope | Add-UcsServiceProfileFromTemplate -NewName @("VMW-C1-N7") -DestinationOrg $SiteName
Get-UcsOrg -Name $SiteName | Get-UcsServiceProfile -Name "VMWare-Cluster1" -LimitScope | Add-UcsServiceProfileFromTemplate -NewName @("VMW-C1-N8") -DestinationOrg $SiteName

#Associate Servers
Get-UcsOrg -name $SiteName | Get-UcsServiceProfile -Name "VMW-C1-N1" -LimitScope | Add-UcsLsBinding -ModifyPresent  -PnDn "sys/chassis-1/blade-1" -RestrictMigration "no"
Get-UcsOrg -name $SiteName | Get-UcsServiceProfile -Name "VMW-C1-N2" -LimitScope | Add-UcsLsBinding -ModifyPresent  -PnDn "sys/chassis-1/blade-2" -RestrictMigration "no"
Get-UcsOrg -name $SiteName | Get-UcsServiceProfile -Name "VMW-C1-N3" -LimitScope | Add-UcsLsBinding -ModifyPresent  -PnDn "sys/chassis-1/blade-3" -RestrictMigration "no"
Get-UcsOrg -name $SiteName | Get-UcsServiceProfile -Name "VMW-C1-N4" -LimitScope | Add-UcsLsBinding -ModifyPresent  -PnDn "sys/chassis-1/blade-4" -RestrictMigration "no"
Get-UcsOrg -name $SiteName | Get-UcsServiceProfile -Name "VMW-C1-N5" -LimitScope | Add-UcsLsBinding -ModifyPresent  -PnDn "sys/chassis-1/blade-5" -RestrictMigration "no"
Get-UcsOrg -name $SiteName | Get-UcsServiceProfile -Name "VMW-C1-N6" -LimitScope | Add-UcsLsBinding -ModifyPresent  -PnDn "sys/chassis-1/blade-6" -RestrictMigration "no"
Get-UcsOrg -name $SiteName | Get-UcsServiceProfile -Name "VMW-C1-N7" -LimitScope | Add-UcsLsBinding -ModifyPresent  -PnDn "sys/chassis-1/blade-7" -RestrictMigration "no"
Get-UcsOrg -name $SiteName | Get-UcsServiceProfile -Name "VMW-C1-N8" -LimitScope | Add-UcsLsBinding -ModifyPresent  -PnDn "sys/chassis-1/blade-8" -RestrictMigration "no"

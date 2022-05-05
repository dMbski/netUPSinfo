unit upsinfo_def;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, synautil, TypInfo;

const
  UPSinfo_UnkVal = -1;     {unkown value const}

  UPSinfo_ResOK = 1;       {result ok}
  UPSinfo_ResErr = 0;      {some error}

type

  TUPSNetServiceType = (
    UPS_Any,
    UPS_PowerMaster,
    UPS_NUT
    );

  TUPSdevicestatusType = (
    UPS_StatusUnknown,   {unknown status}
    UPS_StatusOL,        {UPS online, normal work}
    UPS_StatusOB,        {UPS works on battery}
    UPS_StatusOBnc,      {UPS offline, after working on battery}{maybe off already}
    UPS_StatusShutdown   {UPS shutdowns, check Timer}
    );

  TUPSbatterystatusType = (
    UPS_BattStatusUnk,    {Unknown status}
    UPS_BattStatusOk,     {normal work, nothing happening }
    UPS_BattDisChrg,      {battery discharging, ups working OB}
    UPS_BattCharging,     {battery charging, ups working OL after OB}
    UPS_BattNeedRepl      {old battery, needs replacement}
    );


  { battery }
  TUPSbatteryType = record
    Charge: double;                 {capacity (charge) left %}
    Replaced: string;               {battery replacement date}
    Runtime: double;                {Remaing runtime seconds sec}
    Status: TUPSbatterystatusType;  {battery status}
    Voltage: double;                {current battery voltage V}
    VoltageNominal: double;         {nominal battery voltage ex. 12}
  end;
  PTUPSbatteryType = ^TUPSbatteryType;

  { device }
  TUPSdeviceType = record
    Id: string;                     {device identifier (suid or ups.id)}
    Desc: string;                   {device description }
    Model: string;                  {model name}
    Firmware: string;               {firmware version}
    Serial: string;                 {serial number}
    MFR: string;                    {device manufacturer}
    Temperature: double;            {device temperature}
    Timer: integer;                 {time to shutdown ups (reboot, shutdown) sec}
    StatusRaw: string;              {device status in raw form from received data}
    Status: TUPSdevicestatusType;   {device status}
  end;
  PTUPSdeviceType = ^TUPSdeviceType;

  { output }
  TUPSoutputType = record
    Frequency: double;       {output frequency Hz}
    Current: double;         {output current A}
    CurrentNominal: double;  {output current rating, max A}
    Load: double;            {output load on %}
    Power: double;           {output power W}
    PowerNominal: double;    {output power rating, max W}
    Voltage: double;         {output voltage V}
    VoltageNominal: double;  {output nominal voltage V}
  end;
  PTUPSoutputType = ^TUPSoutputType;

  { input}
  TUPSinputType = record
    Frequency: double;  {input frequency Hz}
    Current: double;    {input current A}
    CurrentNominal: double; {current rating, max A}
    Load: double;       {input load on %}
    Voltage: double;    {input voltage V}
    VoltageNominal: double;   {nominal voltage V}
  end;

  PTUPSinputType = ^TUPSinputType;


{returns current value of system timer with presission 1 sec}
function TickNow: longword;
function TickStr(tick: longword = 0): string;
{returns difference (seconds) between two ticks }
function TickElapsed(tthen: longword; tnow: longword = 0): longword;

{returns TUPSbatterystatusType as description}
function GetStatDescBatt(var stat: TUPSbatterystatusType): string;
{returns TUPSdevicestatusType as description}
function GetStatDescDevice(var stat: TUPSdevicestatusType): string;

procedure CloneDevice(src: PTUPSdeviceType; dst: PTUPSdeviceType);
procedure CloneInput(src: PTUPSinputType; dst: PTUPSinputType);
procedure CloneOutput(src: PTUPSoutputType; dst: PTUPSoutputType);
procedure CloneBattery(src: PTUPSbatteryType; dst: PTUPSbatteryType);

implementation

function TickStr(tick: longword): string;
begin
  if tick = 0 then
    tick := TickNow;
  Result := IntToStr(tick);
end;

function TickNow: longword;
begin
  Result := GetTick div 1000;
end;

function TickElapsed(tthen: longword; tnow: longword): longword;
begin
  begin
    if tnow = 0 then
      tnow := TickNow;
    Result := 0;
    if tnow > tthen then
      Result := (tnow - tthen)
    else
      Result := (tthen - tnow);
  end;
end;

function GetStatDescBatt(var stat: TUPSbatterystatusType): string;
begin
  //Result := GetEnumName(typeInfo(TUPSbatterystatusType), Ord(stat));
  case stat of
    UPS_BattStatusUnk:
      Result := 'Unknown';
    UPS_BattStatusOk:
      Result := 'Ok';
    UPS_BattDisChrg:
      Result := 'Discharging';
    UPS_BattCharging:
      Result := 'Charging';
    UPS_BattNeedRepl:
      Result := 'Require replacm.';
  end;

end;

function GetStatDescDevice(var stat: TUPSdevicestatusType): string;
begin
  //Result := GetEnumName(typeInfo(TUPSdevicestatusType), Ord(stat));
  case stat of
    UPS_StatusUnknown:
    Result := 'Unknown';
    UPS_StatusOL:
    Result := 'Online';
    UPS_StatusOB:
    Result := 'On Battery';
    UPS_StatusOBnc:
    UPS_StatusShutdown:
  end;

end;

procedure CloneDevice(src: PTUPSdeviceType; dst: PTUPSdeviceType);
begin
  if not (Assigned(src)) or not (Assigned(dst)) then
    Exit;

  dst^.Id := src^.Id;
  dst^.Desc := src^.Desc;
  dst^.Model := src^.Model;
  dst^.Firmware := src^.Firmware;
  dst^.Serial := src^.Serial;
  dst^.MFR := src^.MFR;
  dst^.Temperature := src^.Temperature;
  dst^.Timer := src^.Timer;
  dst^.StatusRaw := src^.StatusRaw;
  dst^.Status := src^.Status;
end;

procedure CloneInput(src: PTUPSinputType; dst: PTUPSinputType);
begin
  if not (Assigned(src)) or not (Assigned(dst)) then
    Exit;
  dst^.Frequency := src^.Frequency;
  dst^.Current := src^.Current;
  dst^.CurrentNominal := src^.CurrentNominal;
  dst^.Load := src^.Load;
  dst^.Voltage := src^.Voltage;
  dst^.VoltageNominal := src^.VoltageNominal;
end;

procedure CloneOutput(src: PTUPSoutputType; dst: PTUPSoutputType);
begin
  if not (Assigned(src)) or not (Assigned(dst)) then
    Exit;

  dst^.Frequency := src^.Frequency;
  dst^.Current := src^.Current;
  dst^.CurrentNominal := src^.CurrentNominal;
  dst^.Load := src^.Load;
  dst^.Power := src^.Power;
  dst^.PowerNominal := src^.PowerNominal;
  dst^.Voltage := src^.Voltage;
  dst^.VoltageNominal := src^.VoltageNominal;
end;

procedure CloneBattery(src: PTUPSbatteryType; dst: PTUPSbatteryType);
begin
  if not (Assigned(src)) or not (Assigned(dst)) then
    Exit;
  dst^.Charge := src^.Charge;
  dst^.Replaced := src^.Replaced;
  dst^.Runtime := src^.Runtime;
  dst^.Status := src^.Status;
  dst^.Voltage := src^.Voltage;
  dst^.VoltageNominal := src^.VoltageNominal;
end;


end.

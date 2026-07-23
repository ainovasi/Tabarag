unit uFaqModel;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes;

type
  TFaqItem = class
  private
    FId: Integer;
    FTanya: String;
    FJawaban: String;
    FReferensi: String;
  public
    constructor Create; overload;
    constructor Create(AId: Integer; const ATanya, AJawaban, AReferensi: String); overload;

    property Id: Integer read FId write FId;
    property Tanya: String read FTanya write FTanya;
    property Jawaban: String read FJawaban write FJawaban;
    property Referensi: String read FReferensi write FReferensi;
  end;

  TFaqSearchResult = class(TFaqItem)
  private
    FRrfScore: Double;
  public
    property RrfScore: Double read FRrfScore write FRrfScore;
  end;

implementation

constructor TFaqItem.Create;
begin
  FId := 0;
  FTanya := '';
  FJawaban := '';
  FReferensi := '';
end;

constructor TFaqItem.Create(AId: Integer; const ATanya, AJawaban, AReferensi: String);
begin
  FId := AId;
  FTanya := ATanya;
  FJawaban := AJawaban;
  FReferensi := AReferensi;
end;

end.

unit uJsonHelper;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, fpjson, jsonparser;

type
  TJsonHelper = class
  public
    class function ExtractEmbedding(const AJsonString: String): String;
    class function EscapeJsonString(const AText: String): String;
  end;

implementation

class function TJsonHelper.ExtractEmbedding(const AJsonString: String): String;
var
  Parser: TJSONParser;
  JRoot: TJSONObject;
  JDataArray: TJSONArray;
  JDataItem: TJSONObject;
  JEmbeddingArray: TJSONArray;
begin
  Result := '';
  if AJsonString = '' then Exit;

  Parser := TJSONParser.Create(AJsonString);
  try
    try
      JRoot := Parser.Parse as TJSONObject;
      if Assigned(JRoot) and (JRoot.Find('data') <> nil) then
      begin
        JDataArray := JRoot.Arrays['data'];
        if Assigned(JDataArray) and (JDataArray.Count > 0) then
        begin
          JDataItem := JDataArray.Objects[0];
          if Assigned(JDataItem) and (JDataItem.Find('embedding') <> nil) then
          begin
            JEmbeddingArray := JDataItem.Arrays['embedding'];
            if Assigned(JEmbeddingArray) then
              Result := JEmbeddingArray.AsJSON;
          end;
        end;
      end;
    except
      Result := '';
    end;
  finally
    Parser.Free;
  end;
end;

class function TJsonHelper.EscapeJsonString(const AText: String): String;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to Length(AText) do
  begin
    case AText[i] of
      '"':  Result := Result + '\"';
      '\':  Result := Result + '\\';
      '/':  Result := Result + '\/';
      #8:   Result := Result + '\b';
      #9:   Result := Result + '\t';
      #10:  Result := Result + '\n';
      #12:  Result := Result + '\f';
      #13:  Result := Result + '\r';
    else
      Result := Result + AText[i];
    end;
  end;
end;

end.

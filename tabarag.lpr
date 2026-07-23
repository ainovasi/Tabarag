program tabarag;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  {$IFDEF HASAMIGA}
  athreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, uMainForm, uJsonHelper, uFaqModel, uChatModel, uDBConnection,
  uDBTables, uEmbeddingService, uFaqService, uChatService, uFaqForm,
  uChatLLMService, uServiceManagerForm, uFaqListForm
  { you can add units after this };

{$R *.res}

begin
  RequireDerivedFormResource:=True;
  Application.Scaled:=True;
  {$PUSH}{$WARN 5044 OFF}
  Application.MainFormOnTaskbar:=True;
  {$POP}
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Application.CreateForm(TFaqForm, FaqForm);
  Application.CreateForm(TServiceManagerForm, ServiceManagerForm);
  Application.CreateForm(TFaqListForm, FaqListForm);
  Application.Run;
end.


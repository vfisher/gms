ALTER PROCEDURE [dbo].[t_SaleOnEvent](@EventID int, @DocCode int, @ChID bigint, @CRID int, @AppCode INT, @AXml XML)
AS
/* Процедура, вызываемая при различных событиях в Торговых модулях */
BEGIN
/*
 ---=== Входящие данные ===---
 События
 */
  DECLARE /* @SALE_EVENT... */ 
  @SALE_EVENT_APP_START tinyint = 1,               /* Старт приложения */
  @SALE_EVENT_APP_START_SHOW_MAINFORM tinyint = 2, /* Отображение главной формы при старте */
  @SALE_EVENT_APP_FINISH tinyint = 100,            /* Завершение работы приложения */
  @SALE_EVENT_ON_IDLE tinyint = 10,                /* по таймеру для отображения рекламы на РРО и других действиях */
  @SALE_EVENT_PROCESSING_IS_ONLINE tinyint = 20,   /* Processing is online */
  @SALE_EVENT_PROCESSING_IS_OFFLINE tinyint = 21,  /* Processing is offline */
  @SALE_EVENT_BEFORE_CLOSE tinyint = 30,           /* Событие начала закрытия чека */
  @SALE_EVENT_AFTER_CLOSE tinyint = 31,            /* Событие окончания закрытия чека */
  @SALE_EVENT_BEFORE_RECEXP tinyint = 40,          /* Событие начала денежного вноса\выноса */
  @SALE_EVENT_ON_RECEXP tinyint = 41,              /* Событие денежного вноса\выноса */
  @SALE_EVENT_BEFORE_ZREP tinyint = 50,            /* Событие начала Z-отчёта */
  @SALE_EVENT_BEFORE_CALC_INV tinyint = 60,        /* Событие начала расчёта инвентаризации */
  @SALE_EVENT_ON_CREATE_INV tinyint = 61,          /* Событие создания инвентаризации */
  @SALE_EVENT_ON_EDIT_INV tinyint = 62,            /* Событие редактирования инвентаризации */
  @SALE_EVENT_AFTER_CUSTOM_PRINTFORM tinyint = 70, /* После отображения произвольной печатки */
  @SALE_EVENT_ON_CUSTOM_QRCODE tinyint = 90,       /* Обработка значнения, соответствующего UniInpit с кодом 72 */
  @SALE_EVENT_ON_CUSTOM_QRCODE2 tinyint = 91,      /* Обработка значнения, соответствующего UniInpit с кодом 73 */
  @SALE_EVENT_ON_CUSTOM_QRCODE3 tinyint = 92,      /* Обработка значнения, соответствующего UniInpit с кодом 74 */
  @SALE_EVENT_ON_CUSTOM_REPORTS tinyint = 200,     /* Нажатие кнопки "Разное" в меню Дополнительно */
  @SALE_EVENT_AFTER_PRODADD int = 1000             /* После добавления товара */

/*
 @AXml - произвольные данные, например, код ответа на диалоговое сообщение
 В формате <xml><result>1</result><value>test</value><cookies>произвольные_данные</cookies></xml>

 ---=== Возвращаемые поля ===---
 Msg - текст сообщения, рекламы, путь к печатке, описание поля ввода значения
 Action int - код действия      
 */
  DECLARE 
  @EVENT_ACTION_NONE tinyint = 0,                     /* ничего не делать */
  @EVENT_ACTION_SHOWMESSAGE tinyint = 1,              /* показать сообщение без возврата в t_SaleOnevent */
  @EVENT_ACTION_SHOWDIALOG tinyint = 2,               /* показать диалог (см. google:MessageDlg), возврат в t_SaleOnevent */
  @EVENT_ACTION_SHOWPRINTFORM tinyint = 3,            /* показать печатку, которая лежит по пути Msg */
  @EVENT_ACTION_ENTERVALUE tinyint = 4,               /* диалог ввода значения */
  @EVENT_ACTION_ENTERPWDQR tinyint = 5,               /* eva запросить пароля через QR */
  @EVENT_ACTION_ENTERPWD tinyint = 6,                 /* eva запрос пароля через QR */
  @EVENT_ACTION_UNIINPUT tinyint = 7,                 /* обработка значения через uniInput, как будто оно введено пользователем */ 
  @EVENT_ACTION_BUTTONLIST tinyint = 8,               /* список с кнопками. Можно использовать для построения меню. В @value вернется имя кнопки */
  @EVENT_ACTION_MULTI_UNIINPUT tinyint = 9,           /* ввод сразу нескольких значений */
  @EVENT_ACTION_DISPLAY_ON_RRO tinyint = 10,          /* отобразить текст на дисплее РРО */
  @EVENT_ACTION_CREXTRA tinyint = 11,                 /* произвольный отчет на РРО */
  @EVENT_ACTION_OPEN_MONEY_CONTROL_BOOK tinyint = 12, /* eva - открытие формы при нажатии кнопки "Разное" -> "ЖУКД" в меню Дополнительно */
  --@EVENT_ACTION_OPEN_FIND_PROD_INFO tinyint = 13,     /* не реализовано открыть окно с информацией о товаре */ 
  @EVENT_ACTION_GETFROMAPI tinyint = 19,              /* получить документ из api-сервера gms */ 
  @EVENT_ACTION_GOTOCHEQUE tinyint = 20,              /* переход к чеку */ 
  --@EVENT_ACTION_REFRESH = 21,                       /* не реализовано */
  @EVENT_ACTION_AUTOCLOSE_DOC tinyint = 22,           /* автоматический переход и автозакрытие чека */
  @EVENT_ACTION_ABORT int = 9999                      /* прервать выполенение текущей операции без отображения ошибки */
  
/*
 DlgType int - тип отображаемого диалога (см. google:MessageDlg) */
 DECLARE
   @mtWarning tinyint = 0,
   @mtError tinyint = 1,
   @mtInformation tinyint = 2,
   @mtConfirmation tinyint = 3
/* При возврате EVENT_ACTION_SHOWDIALOG:
   Buttons int - набор кнопок для диалога */
DECLARE
   @mbYes tinyint = 1,
   @mbNo tinyint = 2,
   @mbOK tinyint = 4,
   @mbCancel tinyint = 8,
   @mbAbort tinyint = 16,
   @mbRetry tinyint = 32,
   @mbIgnore tinyint = 64,
   @mbAll tinyint = 128,
   @mbNoToAll int = 256,
   @mbYesToAll int = 512,
   @mbHelp int = 1024,
   @mbClose int = 2048
/*     Пример 'Да, Нет, Отмена' = mbYes + mbNo + mbCancel = 1 + 2 + 8 = 11 
 При возврате EVENT_ACTION_ENTERVALUE:
   Value varchar(max)- значение, которым можно инициализировать диалог ввода (значение по-умолчанию)
   Caption varchar(max) - заголовок окна (опционально)
   Notes varchar(max) - 
   OnlyNumbers bit - ввод только чисел
   InitWithValue bit - подставить в поле ввода значение по-умолчанию, переданное в Value
   ShowNotes bit - отобразить Notes
 Cookies varchar(max) - произвольный идентификатор диалога (аналог cookies). Будет передан неизменно вместе с результатом диалога
 AXML
   result */
  DECLARE    
  @idOK tinyint       = 1,
    @idCancel tinyint   = 2,
  @idAbort tinyint    = 3,
    @idRetry tinyint    = 4,
    @idIgnore tinyint   = 5,
    @idYes tinyint      = 6,
    @idNo tinyint       = 7,
    @idClose tinyint    = 8,
    @idHelp tinyint     = 9,
    @idTryAgain tinyint = 10,
    @idContinue tinyint = 11,
    @mrNone tinyint     = 0,
    @mrOk tinyint,
    @mrCancel tinyint,
    @mrAbort tinyint,
    @mrRetry tinyint,
    @mrIgnore tinyint,
  @mrYes tinyint,
    @mrNo tinyint,
    @mrClose tinyint,
    @mrHelp tinyint,
    @mrTryAgain tinyint,
    @mrContinue tinyint,
    @mrAll tinyint,
    @mrNoToAll tinyint,
    @mrYesToAll tinyint
  SELECT
    @mrOk       = @idOk,
    @mrCancel   = @idCancel,
    @mrAbort    = @idAbort,
    @mrRetry    = @idRetry,
    @mrIgnore   = @idIgnore,
    @mrYes      = @idYes,
    @mrNo       = @idNo,
    @mrClose    = @idClose,
    @mrHelp     = @idHelp,
    @mrTryAgain = @idTryAgain,
    @mrContinue = @idContinue,
    @mrAll      = @mrContinue + 1,
    @mrNoToAll  = @mrAll + 1,
    @mrYesToAll = @mrNoToAll + 1


DECLARE @value VARCHAR(Max)
DECLARE @result INT    
DECLARE @cookies VARCHAR(Max)

SET @result = -1
SET @cookies = null   
IF @AXml IS NOT NULL
  SELECT 
    @value = n.value('value[1]', 'varchar(max)') 
  , @result = n.value('result[1]', 'int') 
  , @cookies = n.value('cookies[1]', 'varchar(max)')  
  FROM @AXml.nodes('/xml') AS t(n)

  ----------- Полезная нагрузка  --------------------------------------------
/*
  Пример отображения кнопочного меню: 

          declare @json varchar(4000)
          set @json = '{ "buttons": [ {"caption":"Бланк выдачи", "name":"Button1", "hotkey":"F1"},
                                 {"caption":"Чек отбора", "name":"Button2", "hotkey":"F2"},
                  ]
             }'

        -- В msg описание кнопок, [Action] = показать кнопки, [Caption] - заголовок окна
        SELECT @json Msg, @EVENT_ACTION_BUTTONLIST [Action], 'Разное' Caption, '<blanc><step>1</step></blanc>' cookies
*/


END
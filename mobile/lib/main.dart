import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'models.dart';
import 'store.dart';
import 'reminders.dart';
import 'batch_session.dart';

const ink = Color(0xFF173C3C), teal = Color(0xFF087F78), paper = Color(0xFFF5F7F3);
final store = StudyStore();
final reminders = Reminders();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await store.init();
    runApp(const DentStudy());
  } catch(e) {
    runApp(MaterialApp(home:Scaffold(body:Center(child:Padding(padding:const EdgeInsets.all(24),child:Text('本地数据加载失败，请保留数据并联系维护者。\n$e'))))));
  }
}

class DentStudy extends StatelessWidget {
  const DentStudy({super.key});
  @override Widget build(BuildContext context) => MaterialApp(
    title:'齿间 · 口腔学习', debugShowCheckedModeBanner:false,
    theme:ThemeData(useMaterial3:true, scaffoldBackgroundColor:paper,
      colorScheme:ColorScheme.fromSeed(seedColor:teal, surface:Colors.white),
      appBarTheme:const AppBarTheme(backgroundColor:paper, foregroundColor:ink, elevation:0),
      textTheme:const TextTheme(bodyLarge:TextStyle(fontSize:17,height:1.65,color:ink), bodyMedium:TextStyle(fontSize:14,height:1.5,color:ink)),
      inputDecorationTheme:InputDecorationTheme(filled:true,fillColor:paper,border:OutlineInputBorder(borderRadius:BorderRadius.circular(14),borderSide:BorderSide.none)),
      filledButtonTheme:FilledButtonThemeData(style:FilledButton.styleFrom(padding:const EdgeInsets.symmetric(horizontal:22,vertical:17),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(14))))),
    home:const Home());
}

void message(BuildContext context, String value) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(value)));
Future<void> safely(BuildContext context, Future<void> Function() action) async {
  try { await action(); } catch(e) { if(context.mounted) message(context,e.toString()); }
}
Widget box(Widget child,{Color color=Colors.white}) => Container(width:double.infinity, padding:const EdgeInsets.all(22),
  decoration:BoxDecoration(color:color,borderRadius:BorderRadius.circular(22),border:Border.all(color:ink.withAlpha(12))),child:child);
Widget heading(String text,{String? sub}) => Padding(padding:const EdgeInsets.only(top:26,bottom:14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
  Text(text,style:const TextStyle(fontSize:21,fontWeight:FontWeight.w700,color:ink)),if(sub!=null)Text(sub,style:const TextStyle(color:Colors.blueGrey,fontSize:13))]));
Widget pill(String text) => Container(padding:const EdgeInsets.symmetric(horizontal:10,vertical:5),decoration:BoxDecoration(color:teal.withAlpha(16),borderRadius:BorderRadius.circular(8)),child:Text(text,style:const TextStyle(fontSize:12,color:teal)));

class Home extends StatefulWidget {
  const Home({super.key});
  @override State<Home> createState()=>_HomeState();
}
class _HomeState extends State<Home> with WidgetsBindingObserver {
  int tab=0;
  String subject='全部',tag='全部',type='全部',chapter='全部',school='全部',year='全部',search='';
  bool favorites=false;
  Timer? reminderTimer;
  @override void initState(){super.initState();store.addListener(changed);WidgetsBinding.instance.addObserver(this);WidgetsBinding.instance.addPostFrameCallback((_){if(store.token.isNotEmpty)safely(context,store.sync);changed();});}
  @override void dispose(){reminderTimer?.cancel();store.removeListener(changed);WidgetsBinding.instance.removeObserver(this);super.dispose();}
  void changed(){if(mounted)setState((){});reminderTimer?.cancel();if(store.prefs.getBool('reminders')??false){reminderTimer=Timer(const Duration(milliseconds:500),(){if(mounted)safely(context,()=>reminders.refresh(store));});}}
  @override void didChangeAppLifecycleState(AppLifecycleState state){if(state==AppLifecycleState.resumed){changed();if(store.token.isNotEmpty)safely(context,store.sync);}}
  Future<void> start(List<Question> selected,{bool exam=false,bool review=false,bool fixedDeep=false}) async {
    if(selected.isEmpty){message(context,'当前条件下没有题目');return;}
    final due=store.due;
    if(!review && due.isNotEmpty && selected.any((q)=>store.learning.states[q.id]?.lastDay==null)) {
      message(context,'还有 ${due.length} 道到期题目，完成首页复习后解锁新题');return;
    }
    var sessionQuestions=[...selected];
    if(!exam) {
      var newSlots=store.remainingNew;
      sessionQuestions=sessionQuestions.where((q){
        if(store.learning.states[q.id]?.lastDay!=null)return true;
        if(newSlots==0)return false;
        newSlots--;return true;
      }).toList();
      if(sessionQuestions.isEmpty){
        message(context,'今日新题上限已完成，可在“我的 → 学习设置”调整');return;
      }
    }
    var batch=false;
    if(!exam&&!fixedDeep){
      final choice=await showModalBottomSheet<String>(context:context,builder:(c)=>SafeArea(child:Padding(padding:const EdgeInsets.all(20),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('选择刷题模式',style:TextStyle(fontSize:22,fontWeight:FontWeight.bold)),const SizedBox(height:8),
        const Text('本次题目会遵守今日新题上限与旧题优先规则。'),const SizedBox(height:16),
        ListTile(leading:const Icon(Icons.chrome_reader_mode_outlined),title:const Text('逐题深度模式'),subtitle:const Text('每题立即看解析并标记掌握度'),onTap:()=>Navigator.pop(c,'deep')),
        ListTile(leading:const Icon(Icons.playlist_add_check_circle_outlined),title:const Text('批量刷题模式'),subtitle:const Text('连续作答，整批完成后统一看解析和评级'),onTap:()=>Navigator.pop(c,'batch')),
      ]))));
      if(choice==null)return;
      batch=choice=='batch';
    }
    await Navigator.of(context).push(MaterialPageRoute(builder:(_)=>batch
      ?BatchStudySession(questions:sessionQuestions,store:store,review:review)
      :StudySession(questions:sessionQuestions,exam:exam,review:review)));
    if(mounted){changed(); if(store.token.isNotEmpty) await safely(context,store.sync);}
    if(mounted && (store.prefs.getBool('reminders')??false)) await safely(context,()=>reminders.refresh(store));
  }
  @override Widget build(BuildContext context) => Scaffold(
    appBar:AppBar(title:Row(children:[Container(padding:const EdgeInsets.all(8),decoration:BoxDecoration(color:teal,borderRadius:BorderRadius.circular(12)),child:const Icon(Icons.auto_stories_outlined,color:Colors.white,size:21)),const SizedBox(width:10),const Text('齿间',style:TextStyle(fontWeight:FontWeight.w800)),const SizedBox(width:9),const Text('DENTSTUDY',style:TextStyle(fontSize:10,letterSpacing:2,color:Colors.blueGrey))]),actions:[
      DropdownButtonHideUnderline(child:DropdownButton<String>(value:store.mode,items:['考研','本科期末','执医'].map((m)=>DropdownMenuItem(value:m,child:Text(m,style:const TextStyle(fontSize:14)))).toList(),onChanged:(m){if(m!=null){store.setMode(m);setState((){subject='全部';chapter='全部';school='全部';year='全部';});}})),const SizedBox(width:16)]),
    body:SafeArea(child:Align(alignment:Alignment.topCenter,child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:900),child:ListView(padding:const EdgeInsets.fromLTRB(20,4,20,32),children:[
      if(tab==0)...dashboard(),if(tab==1)...library(),if(tab==2)...notebooks(),if(tab==3)...statistics(),if(tab==4)...profile()])))),
    bottomNavigationBar:NavigationBar(selectedIndex:tab,onDestinationSelected:(i)=>setState((){tab=i;subject='全部';chapter='全部';tag='全部';type='全部';search='';school='全部';year='全部';}),destinations:const[
      NavigationDestination(icon:Icon(Icons.wb_sunny_outlined),selectedIcon:Icon(Icons.wb_sunny),label:'今日'),NavigationDestination(icon:Icon(Icons.grid_view_outlined),label:'题库'),NavigationDestination(icon:Icon(Icons.bookmarks_outlined),label:'题本'),NavigationDestination(icon:Icon(Icons.bar_chart_outlined),label:'学情'),NavigationDestination(icon:Icon(Icons.person_outline),label:'我的')]));
  List<Widget> dashboard(){
    final state=store.learning, due=store.due, day=dayOf(DateTime.now());
    final attempts=state.attempts.where((a)=>dayOf(DateTime.parse(a['at']))==day).toList();
    final objective=attempts.where((a)=>a['correct']!=null).toList();
    final accuracy=objective.isEmpty?'—':'${(objective.where((a)=>a['correct']==true).length/objective.length*100).round()}%';
    final learned=state.states.values.where((s)=>s.lastDay!=null).length;
    final reviewTarget=store.dailyReviewTarget;
    final reviewProgress=reviewTarget==null
      ?(store.todayReviewCount+due.length==0?1.0:store.todayReviewCount/(store.todayReviewCount+due.length))
      :(reviewTarget==0?1.0:min(1,store.todayReviewCount/reviewTarget));
    final newProgress=store.dailyNewLimit==0?1.0:min(1,store.todayNewCount/store.dailyNewLimit);
    final newQuestions=store.bank.where((q)=>state.states[q.id]?.lastDay==null).take(store.remainingNew).toList();
    return [heading('让每一次练习，都记得更久。',sub:'${day.replaceAll('-',' / ')}  ·  先巩固，再进阶'),
      box(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:[const Icon(Icons.autorenew,color:Color(0xFFB6E4D5)),const SizedBox(width:8),const Text('今日学习计划',style:TextStyle(color:Colors.white,fontSize:16)),const Spacer(),pill('间隔复习')]),
        const SizedBox(height:20),RichText(text:TextSpan(children:[TextSpan(text:'${due.length}',style:const TextStyle(fontSize:64,fontWeight:FontWeight.w700,color:Colors.white)),const TextSpan(text:'  道题',style:TextStyle(color:Colors.white70,fontSize:16))])),
        const Text('今日待复习',style:TextStyle(color:Colors.white70)),const SizedBox(height:16),
        _goalProgress('复习进度','${store.todayReviewCount} / ${reviewTarget==null?'无限制':reviewTarget}',reviewProgress),
        const SizedBox(height:14),_goalProgress('新题进度','${store.todayNewCount} / ${store.dailyNewLimit}',newProgress),
        const SizedBox(height:22),
        SizedBox(width:double.infinity,child:FilledButton(style:FilledButton.styleFrom(backgroundColor:const Color(0xFFD7F0BA),foregroundColor:ink),onPressed:()=>due.isEmpty?start(newQuestions):start(due,review:true),child:Text(due.isEmpty?'开始学习新题  →':'开始今日巩固  →'))),
        const SizedBox(height:10),Text(due.isNotEmpty?'完成 ${due.length} 道到期复习后解锁新题':store.remainingNew==0?'今日新题上限已完成':'还可学习 ${store.remainingNew} 道新题',style:const TextStyle(fontSize:12,color:Colors.white70))]),color:ink),
      const SizedBox(height:16),Row(children:[metric('${attempts.length}','今日练习'),const SizedBox(width:12),metric(accuracy,'客观题正确率'),const SizedBox(width:12),metric('$learned','累计学过')]),
      heading('按你的节奏学习',sub:'当前学习方向 · ${store.mode}'),
      Wrap(spacing:10,runSpacing:10,children:[action('章节练习',Icons.menu_book,()=>setState(()=>tab=1)),action('专项突破',Icons.track_changes,()=>setState(()=>tab=1)),action('随机 5 题',Icons.shuffle,(){final qs=[...store.bank]..shuffle(Random());start(qs.take(5).toList());}),action('限时模考',Icons.timer_outlined,()=>choosePaper())]),
      heading('复习节奏'),box(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Wrap(spacing:8,runSpacing:8,children:intervals.map((d)=>pill('$d 天')).toList()),const SizedBox(height:12),const Text('做错 → 次日重来\n蒙对 → 缩短间隔\n完全掌握 → 到期复习后延长间隔',style:TextStyle(fontSize:14,height:1.9)),const SizedBox(height:10),const Text('当天重复答对不跳级；满 14 天后维持 14 天复习。',style:TextStyle(color:Colors.blueGrey,fontSize:12))])),
      const SizedBox(height:20),const Text('演示题库 · 非历年真题\n医学内容与教材出处待专业审核，当前用于体验产品流程。',style:TextStyle(fontSize:12,color:Colors.blueGrey))];
  }
  Widget _goalProgress(String label,String value,double progress)=>Column(children:[
    Row(children:[Text(label,style:const TextStyle(color:Colors.white)),const Spacer(),Text(value,style:const TextStyle(color:Colors.white70))]),
    const SizedBox(height:7),LinearProgressIndicator(value:progress,minHeight:7,borderRadius:BorderRadius.circular(6),color:const Color(0xFFD7F0BA),backgroundColor:Colors.white12)]);
  Widget metric(String value,String label)=>Expanded(child:box(Column(children:[Text(value,style:const TextStyle(fontSize:25,fontWeight:FontWeight.w700,color:ink)),Text(label,style:const TextStyle(fontSize:11,color:Colors.blueGrey))])));
  Widget action(String label,IconData icon,VoidCallback callback)=>OutlinedButton.icon(onPressed:callback,icon:Icon(icon,size:18),label:Text(label),style:OutlinedButton.styleFrom(padding:const EdgeInsets.all(17),side:BorderSide(color:teal.withAlpha(40)),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(14))));
  Widget selector(String label,String value,List<String> values,ValueChanged<String> change)=>DropdownButtonFormField<String>(initialValue:values.contains(value)?value:'全部',isExpanded:true,decoration:InputDecoration(labelText:label,contentPadding:const EdgeInsets.symmetric(horizontal:12,vertical:10)),items:values.map((v)=>DropdownMenuItem(value:v,child:Text(v,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:13)))).toList(),onChanged:(v){if(v!=null)change(v);});
  List<Question> filtered(List<Question> source)=>source.where((q)=>(subject=='全部'||q.subject==subject)&&(tag=='全部'||q.tags.contains(tag))&&(type=='全部'||q.type==type)&&(chapter=='全部'||q.chapter==chapter)&&(school=='全部'||q.data['school']==school)&&(year=='全部'||q.data['year'].toString()==year)&&(search.isEmpty||'${q.stem} ${q.sharedStem} ${q.data['topics'].join(' ')}'.contains(search))).toList();
  List<Widget> filters(){
    final chapters=store.bank.where((q)=>subject=='全部'||q.subject==subject).map((q)=>q.chapter).toSet().toList();
    return [TextField(decoration:const InputDecoration(hintText:'搜索疾病、考点或题干',prefixIcon:Icon(Icons.search)),onChanged:(v)=>setState(()=>search=v.trim())),const SizedBox(height:12),
      Row(children:[Expanded(child:selector('科目',subject,['全部',...subjects],(v)=>setState((){subject=v;chapter='全部';}))),const SizedBox(width:10),Expanded(child:selector('章节',chapter,['全部',...chapters],(v)=>setState(()=>chapter=v)))]),const SizedBox(height:12),
      Row(children:[Expanded(child:selector('题型',type,['全部','A1','A2','A3','A4','B','简答题','案例分析'],(v)=>setState(()=>type=v))),const SizedBox(width:10),Expanded(child:selector('标签',tag,['全部','高频','易混淆','超纲','易错题','案例题','科室考核','复试笔试','助理医师'],(v)=>setState(()=>tag=v)))]),const SizedBox(height:12),
      Row(children:[Expanded(child:selector('院校',school,['全部',...store.bank.map((q)=>q.data['school'] as String?).whereType<String>().toSet()],(v)=>setState(()=>school=v))),const SizedBox(width:10),Expanded(child:selector('年份',year,['全部',...store.bank.map((q)=>q.data['year']).where((v)=>v!=null).map((v)=>v.toString()).toSet()],(v)=>setState(()=>year=v)))]),const SizedBox(height:16)];
  }
  List<Widget> library(){final qs=filtered(store.bank);return[heading('题库',sub:'章节 · 疾病考点 · 套卷 / 当前 ${store.bank.length} 道题'),...filters(),
    Wrap(spacing:8,runSpacing:8,children:[FilledButton.icon(onPressed:()=>start(qs),icon:const Icon(Icons.play_arrow),label:Text('练习筛选结果 · ${qs.length}')),OutlinedButton.icon(onPressed:choosePaper,icon:const Icon(Icons.timer_outlined),label:const Text('套卷模考'))]),const SizedBox(height:16),...questionList(qs)];}
  List<Widget> notebooks(){final s=store.learning;final qs=filtered(store.bank.where((q)=>favorites?s.states[q.id]?.favorite==true:s.states[q.id]?.wrong==true).toList());return[
    heading('我的题本',sub:'错题自动归集，收藏留给重点'),SegmentedButton<bool>(segments:const[ButtonSegment(value:false,label:Text('错题本'),icon:Icon(Icons.history_edu)),ButtonSegment(value:true,label:Text('收藏夹'),icon:Icon(Icons.bookmark_outline))],selected:{favorites},onSelectionChanged:(v)=>setState(()=>favorites=v.first)),const SizedBox(height:18),...filters(),
    FilledButton(onPressed:()=>start(qs,fixedDeep:true),child:Text('练习这 ${qs.length} 道题')),const SizedBox(height:16),...questionList(qs,canRemove:!favorites)];}
  List<Widget> questionList(List<Question> qs,{bool canRemove=false})=>qs.isEmpty?[box(const Text('暂时没有题目。调整筛选条件，或先完成一次练习。'))]:qs.map((q)=>Padding(padding:const EdgeInsets.only(bottom:10),child:Card(elevation:0,margin:EdgeInsets.zero,child:ListTile(contentPadding:const EdgeInsets.all(16),title:Text(q.stem,maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:15,height:1.5)),subtitle:Padding(padding:const EdgeInsets.only(top:8),child:Text('${q.subject} · ${q.type}  ${q.tags.take(2).join(' / ')}',style:const TextStyle(fontSize:11))),trailing:canRemove?IconButton(tooltip:'移出错题本（保留复习排期）',icon:const Icon(Icons.remove_circle_outline),onPressed:()=>safely(context,()=>store.add(q.id,'removeWrong',null))):const Icon(Icons.chevron_right),onTap:()=>start(q.groupId==null?[q]:store.questions.where((x)=>x.groupId==q.groupId).toList()))))).toList();
  Future<void> choosePaper() async {
    final papers=store.bank.map((q)=>q.data['paperId'] as String).toSet();
    final selected=await showModalBottomSheet<String>(context:context,builder:(context)=>SafeArea(child:ListView(shrinkWrap:true,padding:const EdgeInsets.all(20),children:[const Text('选择试卷',style:TextStyle(fontSize:22,fontWeight:FontWeight.bold)),const Text('演示卷限时 15 分钟，正式卷使用导入时配置的时长。'),...papers.map((p)=>ListTile(title:Text(store.bank.firstWhere((q)=>q.data['paperId']==p).data['paperName']),subtitle:Text('${store.bank.where((q)=>q.data['paperId']==p).length} 道题'),trailing:const Icon(Icons.chevron_right),onTap:()=>Navigator.pop(context,p)))])));
    if(selected!=null) await start(store.bank.where((q)=>q.data['paperId']==selected).toList()..sort((a,b)=>(a.data['order'] as int).compareTo(b.data['order'] as int)),exam:true);
  }
  List<Widget> statistics(){
    final s=store.learning; final objective=s.attempts.where((a)=>a['correct']!=null).toList();
    final days=List.generate(7,(i)=>dayOf(DateTime.now().subtract(Duration(days:6-i))));
    final counts=days.map((d)=>s.attempts.where((a)=>dayOf(DateTime.parse(a['at']))==d).length).toList();
    final maxCount=counts.fold<int>(1,max);
    final rows=subjects.map((subject){final ids=store.questions.where((q)=>q.subject==subject).map((q)=>q.id).toSet(); final a=objective.where((a)=>ids.contains(a['questionId'])).toList(); return {'subject':subject,'total':a.length,'correct':a.where((a)=>a['correct']==true).length};}).toList()..sort((a,b)=>((a['total'] as int)==0?2:(a['correct'] as int)/(a['total'] as int)).compareTo((b['total'] as int)==0?2:(b['correct'] as int)/(b['total'] as int)));
    return [heading('学习看得见',sub:'跨学习方向汇总 · 客观题按每次作答统计'),Row(children:[metric('${s.attempts.length}','总练习次数'),const SizedBox(width:12),metric(objective.isEmpty?'—':'${(objective.where((a)=>a['correct']==true).length/objective.length*100).round()}%','客观题正确率')]),heading('近 7 天练习量'),box(SizedBox(height:180,child:Row(crossAxisAlignment:CrossAxisAlignment.end,children:List.generate(7,(i)=>Expanded(child:Column(mainAxisAlignment:MainAxisAlignment.end,children:[Text('${counts[i]}',style:const TextStyle(fontSize:12)),const SizedBox(height:5),Container(height:max(4,110*counts[i]/maxCount).toDouble(),width:22,decoration:BoxDecoration(color:i==6?teal:const Color(0xFFB9D8CE),borderRadius:BorderRadius.circular(6))),const SizedBox(height:10),Text(days[i].substring(5),style:const TextStyle(fontSize:10,color:Colors.blueGrey))])))))),heading('薄弱科目',sub:'按正确率升序排列；主观题不计入自动正确率'),box(Column(children:rows.map((r){final n=r['total'] as int;final rate=n==0?0.0:(r['correct'] as int)/n;return Padding(padding:const EdgeInsets.symmetric(vertical:10),child:Column(children:[Row(children:[Expanded(child:Text(r['subject'] as String)),Text(n==0?'未练习':'${(rate*100).round()}% · $n 次',style:const TextStyle(fontSize:12,color:Colors.blueGrey))]),const SizedBox(height:8),LinearProgressIndicator(value:rate,minHeight:6,borderRadius:BorderRadius.circular(5),color:rate<0.6?const Color(0xFFD99455):teal,backgroundColor:paper)]));}).toList()))];
  }
  List<Widget> profile()=>[heading('把进步留在每一天',sub:store.email.isEmpty?'当前为本机访客模式':store.email),box(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(store.syncMessage),const SizedBox(height:10),Text('待同步记录：${store.pending.length} 条',style:const TextStyle(fontSize:12,color:Colors.blueGrey)),const SizedBox(height:16),Wrap(spacing:10,runSpacing:10,children:[FilledButton(onPressed:store.syncing?null:()=>store.token.isEmpty?accountDialog():safely(context,store.sync),child:Text(store.syncing?'同步中…':store.token.isEmpty?'登录 / 注册':'立即同步')),if(store.token.isNotEmpty)OutlinedButton(onPressed:store.syncing?null:()=>safely(context,store.importGuest),child:const Text('导入本机访客记录')),if(store.token.isNotEmpty)TextButton(onPressed:()=>safely(context,store.logout),child:const Text('退出登录'))])])),heading('学习设置'),box(Column(children:[
    ListTile(contentPadding:EdgeInsets.zero,leading:const Icon(Icons.flag_outlined),title:const Text('每日学习目标'),subtitle:Text('新题上限 ${store.dailyNewLimit} · 复习目标 ${store.dailyReviewTarget==null?'无限制':store.dailyReviewTarget}'),onTap:goalsDialog),const Divider(),
    SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('每日复习提醒'),subtitle:const Text('本地通知 · 北京时间 20:00 · 未来 14 天'),value:store.prefs.getBool('reminders')??false,onChanged:(v)=>safely(context,()async{if(v && !await reminders.enable())throw Exception('通知权限未获允许，请在系统设置中开启');await store.prefs.setBool('reminders',v);await reminders.refresh(store);changed();})),const Divider(),ListTile(contentPadding:EdgeInsets.zero,leading:const Icon(Icons.download_for_offline_outlined),title:const Text('下载 / 更新离线题库'),subtitle:Text('已缓存 ${store.questions.length} 道题；断网可答题'),onTap:()=>safely(context,()async{await store.download();if(mounted)message(context,'离线题库已更新');})),ListTile(contentPadding:EdgeInsets.zero,leading:const Icon(Icons.dns_outlined),title:const Text('配置后端地址'),subtitle:Text(store.baseUrl),onTap:apiDialog)])),heading('关于题库'),box(const Text('当前内置的是演示习题，不代表院校真题或权威答案。正式题库需完成授权、解析审核与教材版本/章节/页码核对。\n\n研究生科室考核、复试笔试可在考研模式下按标签筛选；执医模式可筛选助理医师。\n\n当前提供本地提醒；跨设备服务端推送需接入 APNs / FCM 等服务。',style:TextStyle(fontSize:13,height:1.8)))];
  Future<void> goalsDialog() async {
    final newField=TextEditingController(text:'${store.dailyNewLimit}');
    final reviewField=TextEditingController(text:'${store.dailyReviewTarget??20}');
    var unlimited=store.dailyReviewTarget==null;
    final result=await showDialog<(int,int?)>(context:context,builder:(c)=>StatefulBuilder(builder:(c,set)=>AlertDialog(title:const Text('每日学习目标'),content:Column(mainAxisSize:MainAxisSize.min,children:[
      TextField(controller:newField,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'每日新题上限（0–100）')),
      const SizedBox(height:12),SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('复习题不设上限'),value:unlimited,onChanged:(v)=>set(()=>unlimited=v)),
      if(!unlimited)TextField(controller:reviewField,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'每日复习题目标（0–200）')),
      const SizedBox(height:8),const Text('到期复习仍需全部完成，才能解锁新题。',style:TextStyle(fontSize:12,color:Colors.blueGrey)),
    ]),actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('取消')),FilledButton(onPressed:(){
      final n=int.tryParse(newField.text),r=unlimited?null:int.tryParse(reviewField.text);
      if(n==null||n<0||n>100||(!unlimited&&(r==null||r<0||r>200))){message(c,'请输入允许范围内的整数');return;}
      Navigator.pop(c,(n,r));
    },child:const Text('保存'))])));
    if(result!=null&&mounted)await safely(context,()async{await store.setGoals(result.$1,result.$2);await reminders.refresh(store);});
  }
  Future<void> apiDialog() async {
    final field=TextEditingController(text:store.baseUrl);
    final value=await showDialog<String>(context:context,builder:(c)=>AlertDialog(title:const Text('后端地址'),content:TextField(controller:field,decoration:const InputDecoration(hintText:'https://api.example.com')),actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('取消')),FilledButton(onPressed:()=>Navigator.pop(c,field.text),child:const Text('保存'))]));
    if(value!=null){final uri=Uri.tryParse(value.trim());if(uri==null||!['https','http'].contains(uri.scheme)||uri.host.isEmpty){if(mounted)message(context,'请输入有效地址');return;}if(store.token.isNotEmpty && value.trim()!=store.baseUrl){if(mounted)message(context,'切换服务器前请先退出登录');return;}store.baseUrl=value.trim();await store.prefs.setString('baseUrl',store.baseUrl);changed();}
  }
  Future<void> accountDialog() async {
    final address=TextEditingController(text:store.baseUrl),email=TextEditingController(),password=TextEditingController();bool register=false,busy=false;String? error;
    await showDialog(context:context,barrierDismissible:false,builder:(c)=>StatefulBuilder(builder:(c,set)=>AlertDialog(title:Text(register?'创建学习账号':'同步学习进度'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:address,decoration:const InputDecoration(labelText:'API 地址')),const SizedBox(height:10),TextField(controller:email,keyboardType:TextInputType.emailAddress,decoration:const InputDecoration(labelText:'邮箱')),const SizedBox(height:10),TextField(controller:password,obscureText:true,decoration:const InputDecoration(labelText:'密码（至少10位）')),const SizedBox(height:10),const Text('登录后访客记录独立保留，可在“我的”中手动导入。',style:TextStyle(fontSize:12)),if(error!=null)Text(error!,style:const TextStyle(color:Colors.red)),TextButton(onPressed:busy?null:()=>set(()=>register=!register),child:Text(register?'已有账号？登录':'没有账号？注册'))])),actions:[TextButton(onPressed:busy?null:()=>Navigator.pop(c),child:const Text('取消')),FilledButton(onPressed:busy?null:()async{set(()=>busy=true);try{await store.login(address.text,email.text,password.text,register);if(c.mounted)Navigator.pop(c);}catch(e){if(c.mounted)set((){error=e.toString();busy=false;});}},child:Text(busy?'连接中…':'继续'))])));
  }
}

class StudySession extends StatefulWidget {
  final List<Question> questions;final bool exam,review;
  const StudySession({super.key,required this.questions,this.exam=false,this.review=false});
  @override State<StudySession> createState()=>_StudySessionState();
}
class _StudySessionState extends State<StudySession> with WidgetsBindingObserver {
  int index=0;bool revealed=false,busy=false,finished=false;
  final Map<String,String> answers={};final Set<String> saved={};
  late DateTime deadline; Timer? timer;int seconds=0;
  Question get q=>widget.questions[index];
  @override void initState(){super.initState();WidgetsBinding.instance.addObserver(this);deadline=DateTime.now().add(Duration(minutes:widget.questions.first.data['durationMinutes'] as int? ?? 15));if(widget.exam){tick();timer=Timer.periodic(const Duration(seconds:1),(_)=>tick());}}
  @override void dispose(){timer?.cancel();WidgetsBinding.instance.removeObserver(this);super.dispose();}
  @override void didChangeAppLifecycleState(AppLifecycleState state){if(state==AppLifecycleState.resumed && widget.exam)tick();}
  void tick(){if(!mounted||finished)return;setState(()=>seconds=max(0,deadline.difference(DateTime.now()).inSeconds));if(seconds==0&&!busy)submitExam();}
  Future<void> save(Question question,String grade,{String mode='practice'})async{
    if(saved.contains(question.id))return;
    await store.add(question.id,'review',{'answer':answers[question.id],'grade':grade,'mode':mode});saved.add(question.id);
  }
  Future<void> grade(String grade) async {
    if(busy)return;setState(()=>busy=true);
    try{await save(q,grade,mode:widget.review?'review':'practice');if(!mounted)return;if(index+1==widget.questions.length)setState(()=>finished=true);else setState((){index++;revealed=false;});}
    catch(e){if(mounted)message(context,'保存失败，请重试：$e');}
    finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> submitExam()async{
    if(busy||finished)return;setState(()=>busy=true);
    try{for(final question in widget.questions){if(question.answer!=null && answers.containsKey(question.id))await save(question,answers[question.id]==question.answer?'guessed':'wrong',mode:'exam');}timer?.cancel();if(mounted)setState(()=>finished=true);}
    catch(e){if(mounted)message(context,'提交失败，作答仍保留在本页：$e');}
    finally{if(mounted)setState(()=>busy=false);}
  }
  Future<bool> leave()async{
    if(finished)return true;
    return await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('结束本次练习？'),content:Text(widget.exam?'尚未交卷的作答不会计分或排期。':'已标记掌握度的题目已保存，当前未提交题目不会保存。'),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('继续')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('结束'))]))??false;
  }
  @override Widget build(BuildContext context)=>PopScope(canPop:finished,onPopInvokedWithResult:(didPop,result)async{if(!didPop && await leave() && context.mounted){setState(()=>finished=true);WidgetsBinding.instance.addPostFrameCallback((_){if(context.mounted)Navigator.pop(context);});}},child:Scaffold(appBar:AppBar(title:Text(finished?'本次练习分析':widget.exam?'限时模考':widget.review?'今日巩固':'专注练习'),actions:[if(widget.exam&&!finished)Padding(padding:const EdgeInsets.all(16),child:Text('${seconds~/60}:${(seconds%60).toString().padLeft(2,'0')}',style:TextStyle(fontWeight:FontWeight.bold,color:seconds<60?Colors.red:ink)))]),body:SafeArea(child:Align(alignment:Alignment.topCenter,child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:800),child:ListView(padding:const EdgeInsets.all(20),children:finished?report():questionView()))))));
  List<Widget> questionView(){final selected=answers[q.id];return[
    Row(children:[Text('${index+1} / ${widget.questions.length}',style:const TextStyle(color:teal,fontWeight:FontWeight.bold)),const Spacer(),Text(q.subject,style:const TextStyle(fontSize:12,color:Colors.blueGrey))]),const SizedBox(height:12),LinearProgressIndicator(value:(index+1)/widget.questions.length,minHeight:4,borderRadius:BorderRadius.circular(4)),const SizedBox(height:24),
    Row(children:[pill(q.type),const SizedBox(width:8),pill(q.data['isDemo']==true?'演示习题':'审核题库'),const Spacer(),IconButton(tooltip:'收藏题目',onPressed:()=>safely(context,()async{await store.add(q.id,'favorite',!(store.learning.states[q.id]?.favorite??false));setState((){});}),icon:Icon(store.learning.states[q.id]?.favorite==true?Icons.bookmark:Icons.bookmark_border,color:teal))]),
    if(q.sharedStem.isNotEmpty)...[const SizedBox(height:16),box(Text(q.sharedStem,style:const TextStyle(fontSize:15,height:1.8)),color:const Color(0xFFE7EFEB))],const SizedBox(height:20),Text(q.stem,style:const TextStyle(fontSize:21,height:1.7,fontWeight:FontWeight.w600,color:ink)),const SizedBox(height:24),
    if(q.answer!=null)...q.options.entries.map((option){final chosen=selected==option.key;final correct=revealed&&option.key==q.answer;final wrong=revealed&&chosen&&!correct;return Padding(padding:const EdgeInsets.only(bottom:12),child:OutlinedButton(onPressed:revealed||busy?null:()=>setState(()=>answers[q.id]=option.key),style:OutlinedButton.styleFrom(disabledForegroundColor:ink,alignment:Alignment.centerLeft,padding:const EdgeInsets.all(18),backgroundColor:correct?const Color(0xFFE0F0E7):wrong?const Color(0xFFFFE9E2):chosen?const Color(0xFFE7F1EE):Colors.white,side:BorderSide(color:correct?teal:wrong?Colors.deepOrange:chosen?teal:const Color(0xFFDDE5DF)),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(15))),child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(option.key,style:const TextStyle(fontWeight:FontWeight.bold)),const SizedBox(width:16),Expanded(child:Text(option.value,style:const TextStyle(fontSize:16,height:1.5)))])));})
    else TextFormField(key:ValueKey(q.id),initialValue:selected,minLines:5,maxLines:10,enabled:!revealed,decoration:const InputDecoration(hintText:'写下你的分析要点，再对照参考答案自评'),onChanged:(v)=>setState(()=>answers[q.id]=v)),
    if(!widget.exam&&!revealed)...[const SizedBox(height:16),FilledButton(onPressed:selected==null||selected.trim().isEmpty?null:()=>setState(()=>revealed=true),child:const Text('确认作答 · 查看解析'))],
    if(revealed)...[heading(q.answer==null?'对照要点，自评掌握度':selected==q.answer?'回答正确，再确认掌握度':'这道题值得再巩固'),...explanation(q),const SizedBox(height:20),Wrap(spacing:8,runSpacing:8,children:[gradeButton('做错','wrong',Colors.deepOrange),gradeButton('蒙对 / 不稳','guessed',const Color(0xFFA77625),enabled:q.answer==null||selected==q.answer),gradeButton('完全掌握','mastered',teal,enabled:q.answer==null||selected==q.answer)]),const SizedBox(height:10),const Text('答错将排入次日复习；只有标记掌握度后才保存本题。',style:TextStyle(fontSize:12,color:Colors.blueGrey)),TextButton.icon(onPressed:editNote,icon:const Icon(Icons.edit_note),label:const Text('写题目笔记'))],
    if(widget.exam)...[const SizedBox(height:24),Row(children:[OutlinedButton(onPressed:index==0||busy?null:()=>setState(()=>index--),child:const Text('上一题')),const Spacer(),FilledButton(onPressed:busy?null:()=>index+1<widget.questions.length?setState(()=>index++):confirmSubmit(),child:Text(index+1==widget.questions.length?'交卷并分析':'下一题'))]),const SizedBox(height:14),Text('已作答 ${answers.values.where((a)=>a.trim().isNotEmpty).length} / ${widget.questions.length} · 到时自动交卷',style:const TextStyle(fontSize:12,color:Colors.blueGrey))]];}
  Widget gradeButton(String text,String value,Color color,{bool enabled=true})=>FilledButton(onPressed:busy||!enabled?null:()=>grade(value),style:FilledButton.styleFrom(backgroundColor:color),child:Text(text));
  List<Widget> explanation(Question question)=>[box(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('参考答案：${question.answer??question.data['rubric']}',style:const TextStyle(fontWeight:FontWeight.bold,color:teal)),const SizedBox(height:12),Text(question.explanation,style:const TextStyle(height:1.8)),const Divider(height:28),Text('易错提示：${question.warning}',style:const TextStyle(fontSize:13,color:Color(0xFFA16736))),const SizedBox(height:12),Text('出处：${question.reference}',style:const TextStyle(fontSize:12,color:Colors.blueGrey)),const SizedBox(height:8),Wrap(spacing:6,runSpacing:6,children:question.tags.map(pill).toList())]))];
  Future<void> editNote()async{final field=TextEditingController(text:store.learning.states[q.id]?.note??'');final value=await showDialog<String>(context:context,builder:(c)=>AlertDialog(title:const Text('个人笔记'),content:TextField(controller:field,minLines:5,maxLines:10,maxLength:10000,decoration:const InputDecoration(hintText:'记录你的理解与易混点')),actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('取消')),FilledButton(onPressed:()=>Navigator.pop(c,field.text),child:const Text('保存'))]));if(value!=null&&mounted)await safely(context,()=>store.add(q.id,'note',value));}
  Future<void> confirmSubmit()async{final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('确认交卷'),content:const Text('未答客观题记 0 分。主观题对照要点自评，不计入自动得分。答对题目先按“蒙对 / 不稳”安排复习。'),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('继续检查')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('交卷'))]));if(ok==true)await submitExam();}
  List<Widget> report(){final objective=widget.questions.where((q)=>q.answer!=null).toList();final correct=objective.where((q)=>answers[q.id]==q.answer).length;final total=objective.fold<int>(0,(sum,q)=>sum+(q.data['points'] as int));final score=objective.where((q)=>answers[q.id]==q.answer).fold<int>(0,(sum,q)=>sum+(q.data['points'] as int));return[
    box(Column(children:[const Icon(Icons.task_alt,color:teal,size:48),const SizedBox(height:16),Text(widget.exam?'客观题 $score / $total 分':'本次练习已完成',style:const TextStyle(fontSize:26,fontWeight:FontWeight.w700)),const SizedBox(height:10),Text('客观题正确 $correct / ${objective.length} · 复习计划已更新'),if(widget.exam)const Text('主观题不包含在自动得分中；请在下方完成自评。',style:TextStyle(fontSize:12,color:Colors.blueGrey))])),heading('逐题回顾'),...widget.questions.map((question)=>Card(elevation:0,child:ExpansionTile(title:Text(question.stem,style:const TextStyle(fontSize:15)),subtitle:Text('你的作答：${answers[question.id]??'未作答'}',maxLines:2,overflow:TextOverflow.ellipsis),children:[Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[...explanation(question),if(widget.exam && question.answer==null && (answers[question.id]?.trim().isNotEmpty??false) && !saved.contains(question.id))...[const SizedBox(height:12),const Text('对照要点后自评（仅保存一次）'),Wrap(spacing:8,children:['wrong','guessed','mastered'].map((g)=>TextButton(onPressed:busy?null:()=>safely(context,()async{setState(()=>busy=true);try{await save(question,g,mode:'exam');}finally{if(mounted)setState(()=>busy=false);}}),child:Text({'wrong':'做错','guessed':'不稳','mastered':'掌握'}[g]!))).toList())],if(saved.contains(question.id))Text('下次复习：${store.learning.states[question.id]?.due??'—'}',style:const TextStyle(color:teal,fontSize:12))]))]))),const SizedBox(height:20),FilledButton(onPressed:()=>Navigator.pop(context),child:const Text('返回学习首页'))];}
}

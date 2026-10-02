import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/services/owner_autopilot_service.dart';
import 'package:zhirox/widgets/app_design.dart';

class OwnerAutoPilotControlCenterScreen extends StatefulWidget {
  const OwnerAutoPilotControlCenterScreen({super.key});
  @override
  State<OwnerAutoPilotControlCenterScreen> createState() => _OwnerAutoPilotControlCenterScreenState();
}

class _OwnerAutoPilotControlCenterScreenState extends State<OwnerAutoPilotControlCenterScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  bool _loading = true;
  String _health = 'all';
  String? _error;
  Map<String, dynamic> _data = const {};

  @override void initState(){super.initState();_refresh();}
  @override void dispose(){_debounce?.cancel();_search.dispose();super.dispose();}
  Map<String,dynamic> _m(dynamic v)=>v is Map?Map<String,dynamic>.from(v):<String,dynamic>{};
  int _n(dynamic v)=>v is num?v.toInt():int.tryParse(v?.toString()??'')??0;

  Future<void> _refresh() async {
    setState((){_loading=true;_error=null;});
    try { final d=await OwnerAutoPilotService.overview(search:_search.text,health:_health); if(mounted)setState(()=>_data=d); }
    catch(e){if(mounted)setState(()=>_error=e.toString().replaceFirst('Exception: ',''));}
    finally{if(mounted)setState(()=>_loading=false);}
  }

  Widget _stat(String label,int value,IconData icon){
    final s=Theme.of(context).colorScheme;
    return Expanded(child:Container(padding:const EdgeInsets.all(10),decoration:BoxDecoration(color:s.surfaceContainerHighest.withValues(alpha:.55),borderRadius:BorderRadius.circular(14)),child:Column(children:[Icon(icon,color:s.primary,size:20),const SizedBox(height:4),Text(value.toString(),style:const TextStyle(fontWeight:FontWeight.w900,fontSize:18)),Text(label,style:Theme.of(context).textTheme.labelSmall,textAlign:TextAlign.center)])));
  }

  Widget _market(Map<String,dynamic> item){
    final s=Theme.of(context).colorScheme,h=_m(item['health']),t=_m(item['telegram']),r=_m(item['risk']),st=_m(item['statements']),nt=_m(item['notifications']);
    final status=h['status']?.toString()??'attention';
    final color=status=='healthy'?const Color(0xFF0B9270):status=='degraded'?const Color(0xFFC47B17):s.error;
    return AppSurface(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[CircleAvatar(backgroundColor:color.withValues(alpha:.12),foregroundColor:color,child:const Icon(Icons.storefront_rounded)),const SizedBox(width:10),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(item['market_name']?.toString()??'مارکێت',style:const TextStyle(fontWeight:FontWeight.w900)),Text(item['admin_name']?.toString()??'',style:Theme.of(context).textTheme.bodySmall)])),Chip(label:Text(status.toUpperCase()),backgroundColor:color.withValues(alpha:.10))]),
      const SizedBox(height:12),
      Row(children:[_stat('Queue',_n(h['active_queue']),Icons.schedule_send_rounded),const SizedBox(width:8),_stat('Retry',_n(h['retrying']),Icons.replay_rounded),const SizedBox(width:8),_stat('Dead-letter',_n(h['dead_letter']),Icons.error_outline_rounded)]),
      const SizedBox(height:10),
      Wrap(spacing:7,runSpacing:7,children:[
        Chip(label:Text('Telegram: '+_n(t['linked_customers']).toString()+' linked')),
        Chip(label:Text('Statement: '+_n(st['completed_30d']).toString()+'/30d')),
        Chip(label:Text('Notifications: '+_n(nt['completed_24h']).toString()+'/24h')),
        Chip(label:Text('Risk: '+_n(r['total']).toString()+' • High '+_n(r['high']).toString()+' • Critical '+_n(r['critical']).toString())),
      ])
    ]));
  }

  @override Widget build(BuildContext context){
    final auth=context.watch<AuthProvider>();
    if(!(auth.user?.getBoolValue('is_system_owner')??false))return Scaffold(appBar:AppBar(title:const Text('AutoPilot Control Center')),body:const Center(child:Text('تەنها System Owner دەستی پێ دەگات.')));
    final o=_m(_data['overview']); final raw=_data['items']; final items=raw is List?raw.whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList():<Map<String,dynamic>>[];
    return Scaffold(appBar:AppBar(title:const Text('AutoPilot Control Center'),actions:[IconButton(onPressed:_loading?null:_refresh,icon:const Icon(Icons.refresh_rounded))]),body:RefreshIndicator(onRefresh:_refresh,child:ListView(physics:const AlwaysScrollableScrollPhysics(),padding:const EdgeInsets.all(16),children:[
      AppSurface(child:Column(children:[Row(children:[_stat('مارکێت',_n(o['total_markets']),Icons.storefront_rounded),const SizedBox(width:8),_stat('Healthy',_n(o['healthy']),Icons.check_circle_outline_rounded),const SizedBox(width:8),_stat('Attention',_n(o['attention']),Icons.warning_amber_rounded)]),const SizedBox(height:8),Row(children:[_stat('Queue',_n(o['active_queue']),Icons.schedule_send_rounded),const SizedBox(width:8),_stat('Dead-letter',_n(o['dead_letter']),Icons.error_outline_rounded),const SizedBox(width:8),_stat('Risk',_n(o['risk_total']),Icons.shield_outlined)])])),
      const SizedBox(height:14),
      TextField(controller:_search,decoration:const InputDecoration(prefixIcon:Icon(Icons.search_rounded),hintText:'گەڕان بە ناوی مارکێت یان بەڕێوەبەر',border:OutlineInputBorder()),onChanged:(_){_debounce?.cancel();_debounce=Timer(const Duration(milliseconds:450),_refresh);}),
      const SizedBox(height:10),
      SegmentedButton<String>(segments:const [ButtonSegment(value:'all',label:Text('هەموو')),ButtonSegment(value:'healthy',label:Text('Healthy')),ButtonSegment(value:'degraded',label:Text('Degraded')),ButtonSegment(value:'attention',label:Text('Attention'))],selected:{_health},onSelectionChanged:(v){setState(()=>_health=v.first);_refresh();}),
      if(_error!=null)...[const SizedBox(height:12),Text(_error!,style:TextStyle(color:Theme.of(context).colorScheme.error,fontWeight:FontWeight.w700))],
      if(_loading&&items.isEmpty)...[const SizedBox(height:40),const Center(child:CircularProgressIndicator())] else if(!_loading&&items.isEmpty)...[const SizedBox(height:40),const Center(child:Text('هیچ مارکێتێک نەدۆزرایەوە'))] else ...[const SizedBox(height:14),for(final item in items)...[_market(item),const SizedBox(height:10)]]
    ])));
  }
}
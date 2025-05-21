//
//  ContentView.swift
//  kanazawa
//
//  Created by 的池秋成 on 2025/04/28.
//

import SwiftUI


import Combine

class DataManager: ObservableObject {
    @Published var current = 0
    @Published var sizeOfMondai = 0

    @Published var id:Int
    @Published var seq:Int
    @Published var selectedJisshiKai:String
    @Published var selectedLevel:String
    @Published var selectedCategory:String
    @Published var selectedKeyWord:String
    @Published var selectedDate:String

    @Published var selectedNumber:String
    @Published var selectedQuestion:String
    @Published var selectedSel1:String
    @Published var selectedSel2:String
    @Published var selectedSel3:String
    @Published var selectedSel4:String

    @Published var selectedAnswer:String
    @Published var selectedDescription:String
    @Published var selectedBikou:String
    @Published var dao = DAO()
    @Published var noEdit:Bool = true
    @Published var kais = [""]
    @Published var levels = [""]
    @Published var categories = [""]
    
    init(){
        self.id = 0
        self.seq = 0
        self.current = 0
        self.sizeOfMondai = 0
        //
        self.selectedJisshiKai = "19"
        self.selectedLevel = "初"
        self.selectedDate = "2023年11月11日"
        self.selectedCategory = "話題・出来事・まちづくり"
        self.selectedKeyWord = "金沢城"
        //
        self.selectedNumber = "1"
        self.selectedQuestion = "「（）」をキャッチフレーズに、1992（平成4）年以来2回目の県内開催となる国民文化祭（いしかわ百万石文化祭2023）の開会式が、2023（令和5）年10月15日に、天皇、皇后両陛下をお迎えし、いしかわ総合スポーツセンターで行われた。"
        self.selectedSel1 = "豪華絢爛"
        self.selectedSel2 = "文化絢燗"
        self.selectedSel3 = "文化創造"
        self.selectedSel4 = "荘厳華麗"
        //
        self.selectedAnswer = "文化絢爛（けんらん）"
        self.selectedDescription = "2023年の国民文化祭は、10月14日から11月26日までを開催期間として、県内全19市町で151の事業が展開された。キャッチフレーズには、加賀百万石の伝統のもとに育まれた多彩な文化が、大会を機にいっそう磨かれ、未来に輝いてほしいとの願いが込められている。"
        self.selectedBikou = "備考"
        //
        self.dao.initial()
        self.dao.select_all()
        self.kais = self.dao.distinct(field_name: "kai")
        self.categories = self.dao.distinct(field_name: "category")
        self.levels = self.dao.distinct(field_name: "level")
        self.current = 0
        self.showcurrent(current: self.current)
    }
    
    func clear_fields(){
        self.selectedJisshiKai = ""
        self.selectedLevel = ""
        self.selectedCategory = ""
        self.selectedNumber = ""
        self.selectedQuestion = ""
        self.selectedSel1 = ""
        self.selectedSel2 = ""
        self.selectedSel3 = ""
        self.selectedSel4 = ""
        self.selectedAnswer = ""
        self.selectedDescription = ""
        self.selectedDate = ""
        self.selectedBikou = ""
        self.selectedKeyWord = ""
    }
    func setData() -> [String]{
        var data = [String]()
        data.append(String(self.seq))
        data.append(self.selectedJisshiKai)
        data.append(self.selectedLevel)
        data.append(self.selectedCategory)
        data.append(self.selectedNumber)
        data.append(self.selectedQuestion)
        data.append(self.selectedSel1)
        data.append(self.selectedSel2)
        data.append(self.selectedSel3)
        data.append(self.selectedSel4)
        data.append(self.selectedAnswer)
        data.append(self.selectedDescription)
        data.append(self.selectedDate)
        data.append(self.selectedBikou)
        return data
    }
    func showcurrent(current:Int){
        //print("debug:\(current)")
        self.id = mondai[current].id
        self.seq = mondai[current].seq
        self.selectedJisshiKai = mondai[current].kai
        self.selectedLevel = mondai[current].level
        self.selectedCategory = mondai[current].category
        self.selectedNumber = String(mondai[current].number)
        self.selectedQuestion = mondai[current].question
        self.selectedSel1 = mondai[current].sel1
        self.selectedSel2 = mondai[current].sel2
        self.selectedSel3 = mondai[current].sel3
        self.selectedSel4 = mondai[current].sel4
        self.selectedAnswer = mondai[current].answer
        self.selectedDescription = mondai[current].description
        self.selectedDate = mondai[current].hiduke
        self.selectedBikou = mondai[current].bikou
        self.sizeOfMondai = mondai.count
        shuffleSels()
        hideAnswer()
   }
    //
    @Published var selectedSels = ["豪華絢爛", "文化絢燗", "文化創造", "荘厳華麗"]
    func shuffleSels(){
        selectedSels[0] = self.selectedSel1
        selectedSels[1] = self.selectedSel2
        selectedSels[2] = self.selectedSel3
        selectedSels[3] = self.selectedSel4
        selectedSels.shuffle()
        selectedIndex = -1
     }
    //
    @Published var selectedIndex = -1
    @Published var altExpre:Bool = false
    func hideAnswer(){
        if (selectedIndex == -1){
            altExpre = false
        }else{
            altExpre = true
        }
    }
}

struct NaviView: View {
    @ObservedObject var dm:DataManager
    var csv = myCSV(fname: "KanazawaData")

    @State private var exportFile: Bool = false
    @State private var importFile: Bool = false
    @State private var text: String = ""
    @State private var stringData: String = ""
    @State private var csvIOoption = ""
    @State private var csvData: [[String]] = []
    private let options = ["入","出"]

    @State private var showAlert = false
    @State private var importedData: [[String]] = []
    @State private var yesnoflag = false

    func yesaction() {
        yesnoflag = false
        print("Yes selected")
    }

    func noaction() {
        yesnoflag = true
        print("No selected")
    }

    func processCSV() {
        if !yesnoflag {
            dm.dao.close()
            dm.dao.initial()
            dm.dao.drop_table()
            dm.dao.create_table()
        }
        for csvdata in importedData {
            if csvdata.count > 1 {
                dm.dao.insert_fromcsv(data: csvdata)
            }
        }
        dm.dao.select_all()
        dm.current = 0
        dm.sizeOfMondai = mondai.count
        dm.kais = dm.dao.distinct(field_name: "kai")
        dm.categories = dm.dao.distinct(field_name: "category")
        dm.levels = dm.dao.distinct(field_name: "level")
        dm.showcurrent(current: dm.current)
    }

    var body: some View {
        HStack{
            Spacer()
            Button("|<<"){
                dm.current = 0
                dm.showcurrent(current: dm.current)
            }.buttonStyle(.bordered)
            Spacer()
            Button("<"){
                if (0<dm.current){
                    dm.current -= 1
                }
                dm.showcurrent(current: dm.current)
            }.buttonStyle(.bordered)
            Spacer()
            Text(String(dm.current+1) + "/" + String(dm.sizeOfMondai))
            Spacer()
            Button(">"){
                if (dm.current<dm.sizeOfMondai-1){
                    dm.current += 1
                }
                dm.showcurrent(current: dm.current)
            }.buttonStyle(.bordered)
            Spacer()
            Button(">>|"){
                dm.current = dm.sizeOfMondai - 1
                dm.showcurrent(current: dm.current)
            }.buttonStyle(.bordered)
            Spacer()
            Menu{
                // https://swappli.com/menu-picker/
                Picker("選択", selection: $csvIOoption){
                    ForEach(options, id: \.self){ option in Text(option) }
                }.pickerStyle(.inline)
            } label: {
                //Text("CSV:")
                Image(systemName: "gearshape").symbolRenderingMode(.monochrome)
                //icon: do { Image(uiImage: ImageRenderer(content: Text("🏠")).uiImage!) }
            }
            if(csvIOoption=="出"){
                Button(csvIOoption) {
                    // ファイルをエクスポートするロジックを実装する
                    stringData = csv.CSVDataGen()
                    exportFile = true
                    importFile = false
                }
                .fileExporter(
                    isPresented: $exportFile,
                    document: SmpFileDocument(text: stringData),
                    contentTypes: [.plainText],
                    defaultFilename: csv.getFName()
                ) { result in
                    // エクスポートの完了時に実行されるコードを定義する
                    switch result {
                    case .success(let file):
                        print(file.absoluteString)
                    case .failure(let error):
                        print(error)
                    }
                }
                onCancellation: {
                    print("cancel success")
                }
            }else if(csvIOoption=="入"){
                Button(csvIOoption) {
                    // ファイルをインポートするロジックを実装する
                    importFile = true
                    exportFile = false
                }.buttonBorderShape(.capsule)
                    .fileImporter(
                        isPresented: $importFile,
                        allowedContentTypes: [.plainText],
                        allowsMultipleSelection: false
                    ) { result in
                        switch result {
                        case .success(let files):
                            guard let file = files.first else { return }
                            // 仮の reshape 読み込み処理
                            let data: [[String]] = csv.reshape(url: file)
                            self.importedData = data
                            self.showAlert = true  // -> アラート表示トリガー

                        case .failure(let error):
                            print("Import error: \(error.localizedDescription)")
                        }
                    }
                    .alert("New or Append", isPresented: $showAlert) {
                        Button("Yes") {
                            yesaction()
                            processCSV()
                        }
                        Button("No", role: .cancel) {
                            noaction()
                            processCSV()
                        }
                    } message: {
                        Text("DBを作り直しますか？")
                    }
            }
        }
    }
}

struct SearchView: View {
    @ObservedObject var dm:DataManager
    
    private let searchObjs = ["全体", "実施回", "級", "分類", "回＆級" ,"回＆級＆分類" ,"キーワード"]
    @State var selectedSearch = ""
    @State var newsave:String = "New"
    @State var editupdate:String = "Edit"
    @State var isSave = false
    @State var isUpdate = false
    @State var isError = false
    
    func search(){
        if selectedSearch==searchObjs[1] {
            dm.dao.select_kai(kai: dm.selectedJisshiKai)
        }else if selectedSearch==searchObjs[2] {
            dm.dao.select_level(level: dm.selectedLevel)
        }else if selectedSearch==searchObjs[3] {
            dm.dao.select_category(category: dm.selectedCategory)
        }else if selectedSearch==searchObjs[4] {
            dm.dao.select_kai_level(kai: dm.selectedJisshiKai, level: dm.selectedLevel)
        }else if selectedSearch==searchObjs[5] {
            dm.dao.select_kai_level_category(kai: dm.selectedJisshiKai, level: dm.selectedLevel, category: dm.selectedCategory)
        }else if selectedSearch==searchObjs[6] {
            dm.dao.select_keyword(keyword: dm.selectedKeyWord)
        }else if selectedSearch==searchObjs[0] {
            dm.dao.select_all()
        }else{
            print("error!")
        }
    }
    func okActionUpdate(){
        let curr = dm.current
        let data = dm.setData()
        dm.dao.update(data: data, id: dm.id)
        search()
        dm.current = curr
        dm.sizeOfMondai = mondai.count
        dm.showcurrent(current: dm.current)
        editupdate = "Edit"
        newsave = "New"
        isUpdate = false
        dm.noEdit = true
    }
    func okActionSave(){
        let curr = dm.current
        let data = dm.setData()
        dm.dao.insert(data: data)
        search()
        //dm.current = curr + 1
        dm.current = curr
        dm.sizeOfMondai = mondai.count
        dm.showcurrent(current: dm.current)
        newsave = "New"
        editupdate = "Edit"
        isSave = false
        dm.noEdit = true
    }
    func okActionDelete(){
        let curr = dm.current
        dm.dao.delete(id: dm.id)
        search()
        dm.current = curr - 1
        dm.sizeOfMondai = mondai.count
        dm.showcurrent(current: dm.current)
        isError = false
    }

    var body: some View {
        VStack{
            HStack{
                Button("検索") {
                    //selectedSearch = searchObjs[6]
                    search()
                    dm.current = 0
                    if mondai.count>0{
                        dm.sizeOfMondai = mondai.count
                        dm.showcurrent(current: dm.current)
                    }else if mondai.count==0{
                        dm.sizeOfMondai = 0
                        mondai.removeAll()
                        dm.clear_fields()
                    }
                    newsave = "New"
                    editupdate = "Edit"
                }.buttonStyle(.bordered)
                Picker(selection: $selectedSearch, label: Text(selectedSearch)) {
                    ForEach (searchObjs, id: \.self) {
                        Text($0).font(.subheadline)
                    }
                }.pickerStyle(.wheel)
                    .frame(width: .infinity, height: 38)
                    .clipped()
                    .contentShape(Rectangle())
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                /* 以下のボタンの表示を有効にもできる（その場合、上の検索Pickerの表示幅を狭めること）
                Button( newsave ) {
                    if newsave=="New" {
                        dm.clear_fields()
                        newsave = "Save"
                        dm.noEdit = false
                    } else if newsave=="Save" {
                        isSave = true
                        dm.noEdit = false
                    }
                }.buttonStyle(.bordered)
                    .alert(isPresented: $isSave){
                        Alert(title:Text("Save?"), message: Text("id=new"+", Kai="+dm.selectedJisshiKai),
                              primaryButton:.default(Text("Ok"),action:{okActionSave()}),
                              secondaryButton:.cancel(Text("Cancel"), action:{}))
                    }
                Button(editupdate) {
                    if editupdate=="Edit"{
                        editupdate = "Updt"
                        newsave = "Save"
                        dm.noEdit = false
                    } else if editupdate=="Updt"{
                        isUpdate = true
                        dm.noEdit = false
                    }
                }.buttonStyle(.bordered)
                    .alert(isPresented: $isUpdate){
                        Alert(title:Text("Update?"), message: Text("id="+String(dm.id)+", Kai="+dm.selectedJisshiKai),
                              primaryButton:.default(Text("Ok"),action:{okActionUpdate()}),
                              secondaryButton:.cancel(Text("Cancel"), action:{}))
                    }
                Button("Del") {
                    isError = true
                }.buttonStyle(.bordered)
                    .alert(isPresented: $isError){
                        Alert(title:Text("Delete?"), message: Text("id="+String(dm.id)+", Kai="+dm.selectedJisshiKai),
                              primaryButton:.default(Text("Ok"),action:{okActionDelete()}),
                              secondaryButton:.cancel(Text("Cancel"), action:{}))
                    }
                */
                
            }.frame(maxWidth: .infinity, alignment: .leading)
            
            HStack{
                Text("回：")
                Picker(selection:$dm.selectedJisshiKai, label: Text(dm.selectedJisshiKai)) {
                    ForEach (dm.kais, id: \.self) {
                        Text($0).font(.subheadline)
                    }
                }.pickerStyle(.wheel)
                .frame(width: 60, height: 38)
                .clipped()
                .contentShape(Rectangle())
                /*
                .onChange(of: dm.selectedJisshiKai) {
                    if dm.selectedJisshiKai.isEmpty {
                        ////isDisableCategory = true
                    } else {
                        //selectedSearch = "実施回"
                        dm.dao.select_kai(kai: dm.selectedJisshiKai)
                        dm.current=0
                        if mondai.count>0{
                            //dm.current=0
                            dm.showcurrent(current: dm.current)
                        }else if mondai.count==0{
                            mondai.removeAll()
                            //dm.current = 0
                            //dm.sizeOfMondai = 0
                            dm.clear_fields()
                        }
                        ////isDisableCategory = false
                    }
                    
                }
                 */
                Text("級：")
                Picker(selection:$dm.selectedLevel, label: Text(dm.selectedLevel)) {
                    ForEach (dm.levels, id: \.self) {
                        Text($0).font(.subheadline)
                    }
                }.pickerStyle(.wheel)
                .frame(width: 60, height: 38)
                .clipped()
                .contentShape(Rectangle())
                /*
                .onChange(of: dm.selectedLevel) {
                    if dm.selectedLevel.isEmpty {
                        ////isDisableCategory = true
                    } else {
                        //selectedSearch = "レベル"
                        dm.dao.select_level(level: dm.selectedLevel)
                        dm.current=0
                        if mondai.count>0{
                            //dm.current=0
                            dm.showcurrent(current: dm.current)
                        }else if mondai.count==0{
                            mondai.removeAll()
                            //dm.current = 0
                            //dm.sizeOfMondai = 0
                            dm.clear_fields()
                        }
                        ////isDisableCategory = false
                    }
                }
                */
                Text(dm.selectedDate)
            }.frame(maxWidth: .infinity, alignment: .center)
            HStack{
                Text("分類：")
                Picker(selection:$dm.selectedCategory, label: Text(dm.selectedCategory)) {
                    ForEach (dm.categories, id: \.self) {
                        Text($0).font(.subheadline)
                    }
                }
                .pickerStyle(.wheel)
                .frame(width: .infinity, height: 38)
                .clipped()
                .contentShape(Rectangle())
                /*
                .onChange(of: dm.selectedCategory) {
                    if dm.selectedCategory.isEmpty {
                        ////isDisableCategory = true
                    } else {
                        //selectedSearch = "分類"
                        dm.dao.select_category(category: dm.selectedCategory)
                        dm.current=0
                        if mondai.count>0{
                            //dm.current=0
                            dm.showcurrent(current: dm.current)
                        }else if mondai.count==0{
                            mondai.removeAll()
                            //dm.current = 0
                            //dm.sizeOfMondai = 0
                            dm.clear_fields()
                        }
                        ////isDisableCategory = false
                    }
                }
                */
            }.frame(maxWidth: .infinity, alignment: .leading)
            
            HStack{
                Text("語句：")
                TextField("キーワード", text: $dm.selectedKeyWord)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .border(.red)
                    .frame(width:280)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ItemView: View {
    @ObservedObject var dm:DataManager

    var body: some View {
        VStack{
            TextField("問題", text: $dm.selectedQuestion, axis: .vertical)
                .font(.system(size: 16))
                .textFieldStyle(.roundedBorder)
                //.padding(.all)
                //.frame(maxWidth: .infinity, alignment: .center)
                .disabled(dm.noEdit)
            HStack{
                Text(dm.selectedNumber+"：")
                VStack{
                    HStack{
                        HStack{
                            Image(systemName: dm.selectedIndex == 0 ? "checkmark.circle.fill" : "circle").foregroundColor(.blue)
                            TextField("選択肢1", text: $dm.selectedSels[0])
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .border(.red)
                                .frame(width:110)
                                .disabled(dm.noEdit)
                            //Text(selectedSel1)
                        }.onTapGesture {
                            dm.selectedIndex = 0
                            dm.altExpre = true
                        }
                        HStack{
                            Image(systemName: dm.selectedIndex == 1 ? "checkmark.circle.fill" : "circle").foregroundColor(.blue)
                            TextField("選択肢2", text: $dm.selectedSels[1])
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .border(.red)
                                .frame(width:110)
                                .disabled(dm.noEdit)
                            //Text(selectedSel2)
                        }.onTapGesture {
                            dm.selectedIndex = 1
                            dm.altExpre = true
                        }
                    }.frame(height: 30)
                    HStack{
                        HStack{
                            Image(systemName: dm.selectedIndex == 2 ? "checkmark.circle.fill" : "circle").foregroundColor(.blue)
                            TextField("選択肢3", text: $dm.selectedSels[2])
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .border(.red)
                                .frame(width:110)
                                .disabled(dm.noEdit)
                            //Text(selectedSel3)
                        }.onTapGesture {
                            dm.selectedIndex = 2
                            dm.altExpre = true
                        }
                        HStack{
                            Image(systemName: dm.selectedIndex == 3 ? "checkmark.circle.fill" : "circle").foregroundColor(.blue)
                            TextField("選択肢4", text: $dm.selectedSels[3])
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .border(.red)
                                .frame(width:110)
                                .disabled(dm.noEdit)
                            //Text(selectedSel4)
                        }.onTapGesture {
                            dm.selectedIndex = 3
                            dm.altExpre = true
                        }
                    }.frame(height: 30)
                }
            }
        }
    }
}

struct InfoView: View {
    @ObservedObject var dm:DataManager
    var body: some View {
        VStack{
            HStack{
                Text("答：")
                TextField("答：", text: $dm.selectedAnswer)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .border(.red)
                    .frame(width:200)
                    .foregroundColor(dm.altExpre ? .primary:Color(UIColor.systemGray6))
                    .background(Color(UIColor.systemGray6))
                    .disabled(dm.noEdit)

            }.frame(maxWidth: .infinity, alignment: .center)
            TextField("解説", text: $dm.selectedDescription, axis: .vertical)
                .font(.system(size: 16))
                .textFieldStyle(.roundedBorder)
                //.padding(.all)
                .foregroundColor(dm.altExpre ? .primary:Color(UIColor.systemGray6))
                .background(Color(UIColor.systemGray6))
                .disabled(dm.noEdit)

        }
    }
}

struct ContentView: View {
    @StateObject var dm = DataManager()
    var body: some View {
        VStack {
            Spacer()
            NaviView(dm: dm)
            Spacer()
            Divider().background(.blue)
            Spacer()
            SearchView(dm: dm)
            Spacer()
            Divider().background(.blue)
            Spacer()
            ItemView(dm: dm)
            Spacer()
            Divider().background(.blue)
            Spacer()
            InfoView(dm: dm)
            Spacer()
        }
        .padding()
        .onTapGesture { UIApplication.shared.closeKeyboard() }
        .gesture(
            DragGesture()
                .onEnded { gesture in
                    let horizontalTranslation = gesture.translation.width
                    let verticalTranslation = gesture.translation.height
                    
                    if abs(horizontalTranslation) > abs(verticalTranslation) {
                        // 水平方向のスワイプ
                        if horizontalTranslation > 0 {
                            // 右にスワイプした場合の処理
                            //self.labelText = "右にスワイプしました"
                            if 0<dm.current{
                                dm.current -= 1
                            }
                            dm.showcurrent(current: dm.current)
                        } else {
                            // 左にスワイプした場合の処理
                            //self.labelText = "左にスワイプしました"
                            if dm.current<mondai.count-1{
                                dm.current += 1
                            }
                            dm.showcurrent(current: dm.current)
                        }
                    } else {
                        // 垂直方向のスワイプ
                        if verticalTranslation > 0 {
                            // 下にスワイプした場合の処理
                            //self.labelText = "下にスワイプしました"
                        } else {
                            // 上にスワイプした場合の処理
                            //self.labelText = "上にスワイプしました"
                        }
                    }
                }
        )
        //.withAnimation(.spring())
    }
}

#Preview {
    ContentView()
}

var fs = require("fs")
var Web3 = require('web3')
var web3 = new Web3()

var host = process.argv[2] || "localhost"

var provider

if (host == "ipc") {
    var net = require('net')
    provider = new web3.providers.IpcProvider(process.argv[3], net)
}
else provider = new web3.providers.HttpProvider('http://' + host + ':8545')

web3.setProvider(provider)

// web3.setProvider(new web3.providers.HttpProvider('http://' + host + ':8545'))

var dir = __dirname + "/contracts/compiled/"

var send_opt

async function createContract(name, args) {
    var code = "0x" + fs.readFileSync(dir + name + ".bin")
    var abi = JSON.parse(fs.readFileSync(dir + name + ".abi"))
    return new web3.eth.Contract(abi).deploy({data: code, arguments:args}).send(send_opt)
}

async function getNetwork() {
    let networkId = await web3.eth.net.getId()
    let networkName
    switch (networkId) {
    case "1":
	networkName = "main";
	break;
    case "2":
	networkName = "morden";
	break;
    case "3":
	networkName = "ropsten";
	break;
    case "4":
	networkName = "rinkeby";
	break;
    case "42":
	networkName = "kovan";
	break;
    default:
	networkName = "development";
    }
    return networkName
}

async function exports(filesystem, tasks, iactive) {
    let exportedContracts = {
	filesystem: {abi: filesystem._jsonInterface, address: filesystem._address.toLowerCase()},
	tasks: {abi: tasks._jsonInterface, address: tasks._address.toLowerCase()},
	interactive: {abi: iactive._jsonInterface, address: iactive._address.toLowerCase()} 
    }
    
    let network = await getNetwork()

    if (!fs.existsSync(__dirname + "/export/")){
	fs.mkdirSync(__dirname + "/export/")
    }

    let path = __dirname + "/export/" + network+ ".json"

    fs.writeFileSync(path, JSON.stringify(exportedContracts), (e) => {if(e) console.error(e) })

}

async function doDeploy() {
    var accts = await web3.eth.getAccounts()
    send_opt = {gas:4700000, from:accts[0], gasPrice:"21000000000"}
    //var test = await createContract("Test")

    var judge = await createContract("Judge")

    var fs = await createContract("Filesystem")
    var iactive = await createContract("Interactive", [judge.options.address])
    var tasks = await createContract("Tasks", [iactive.options.address, fs.options.address])
    //var resubmit = await createContract("TasksResubmit", [iactive.options.address, fs.options.address])
    var merkle = await createContract("Merkle")
    iactive.setProvider(web3.currentProvider)
    var tx = await iactive.methods.registerJudge(1, merkle.options.address).send(send_opt)
    // console.log(tx)
    var config = {
        judge: judge.options.address,
        interactive: iactive.options.address,
        host: host,
        base: send_opt.from,
        tasks: tasks.options.address,
        //resubmit: resubmit.options.address,
        fs: fs.options.address,
        //merkle: merkle.options.address,
        ipfshost: "programming-progress.com",
        events_disabled: false, poll: false,
        timeout: 5000,
        tick: true,
        interpreter_args: [],
    }
    await exports(fs, tasks, iactive)
    if (host == "ipc") config.ipc = process.argv[3]
    console.log(JSON.stringify(config))
    process.exit(0)
}

doDeploy()

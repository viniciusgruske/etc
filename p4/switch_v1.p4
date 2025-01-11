#include <core.p4>
#include <v1model.p4>

/*************************************************************************
*********************** H E A D E R S  ***********************************
*************************************************************************/

typedef bit<9>  egressSpec_t;       // Tipo para especificação de porta de saída (9 bits)
typedef bit<48> macAddr_t;          // Tipo para endereços MAC (48 bits)

// Define cabeçalho Ethernet
header ethernet_t {
    macAddr_t dstAddr;              // Endereço MAC de destino
    macAddr_t srcAddr;              // Endereço MAC de origem
    bit<16>   etherType;            // Tipo Ethernet (identifica o protocolo)
}

// Estruturas para metadados e cabeçalhos
struct metadata { }                 // Metadados (vazio neste caso)
struct headers {
    ethernet_t ethernet;            // Cabeçalho Ethernet
}


/*************************************************************************
*********************** P A R S E R  ***********************************
*************************************************************************/

// Parser para extrair e interpretar os cabeçalhos do pacote
parser MyParser(packet_in packet,
                out headers hdr,
                inout metadata meta,
                inout standard_metadata_t standard_metadata) {

    state start {                       // Estado inicial do parser
        packet.extract(hdr.ethernet);   // Extrai o cabeçalho Ethernet do pacote
        transition accept;              // Transita para o estado de aceitação
    }
}

/*************************************************************************
************   C H E C K S U M    V E R I F I C A T I O N   *************
*************************************************************************/

// Verificação de checksum (vazio no momento)
control MyVerifyChecksum(inout headers hdr, inout metadata meta) {
    apply {  }
}

/*************************************************************************
**************  I N G R E S S   P R O C E S S I N G   *******************
*************************************************************************/

// Processamento de pacotes na fase de ingresso
control MyIngress(inout headers hdr,
                  inout metadata meta,
                  inout standard_metadata_t standard_metadata) {

    // Define uma ação para encaminhar o pacote para uma porta de saída específica
    action forward(egressSpec_t egress_port) {
        standard_metadata.egress_spec = egress_port;
    }

    // Define uma ação para flooding
    // mcast_grp 1 deve ser definido para todas as portas no control plane
    action flooding() {
        standard_metadata.mcast_grp = 1;
    }

    // Tabela para encaminhamento unicast baseado no endereço MAC de destino
    table ethernet_unicast_table {
        key = { hdr.ethernet.dstAddr: exact; }              // Chave é o endereço MAC de destino
        actions = {
            forward;
            flooding;
        }
        size = 1024;                                        // Tamanho máximo da tabela
        default_action = flooding();                        // Ação padrão é flooding
    }

    // Tabela para tratamento de pacotes multicast baseado no endereço MAC
    table ethernet_multicast_table {
        key = { hdr.ethernet.dstAddr: ternary; }            // Chave permite correspondência parcial (ternary)
        actions = {
            flooding;
            NoAction;
        }
        size = 32;                                          // Tamanho máximo da tabela
        default_action = NoAction();                        // Ação padrão é nenhuma
    }

    // Lógica de aplicação das tabelas
    apply {
        if (hdr.ethernet.isValid()) {                       // Verifica se o cabeçalho Ethernet é válido
            if (!ethernet_multicast_table.apply().hit) {    // Aplica a tabela Multicast, se não houver correspondência na tabela multicast
                ethernet_unicast_table.apply();             // Aplica a tabela unicast
            }
        }
    }
}

/*************************************************************************
****************  E G R E S S   P R O C E S S I N G   *******************
*************************************************************************/

// Processamento de pacotes na fase de egresso
control MyEgress(inout headers hdr,
                 inout metadata meta,
                 inout standard_metadata_t standard_metadata) {
    apply {
        // Evita reflexão de pacotes na mesma porta de entrada
        if(standard_metadata.egress_port == standard_metadata.ingress_port) {
            mark_to_drop(standard_metadata);
        }
    }
}

/*************************************************************************
*************   C H E C K S U M    C O M P U T A T I O N   **************
*************************************************************************/

// Computação de checksum (vazio no momento)
control MyComputeChecksum(inout headers  hdr, inout metadata meta) {
     apply {  }
}

/*************************************************************************
***********************  D E P A R S E R  *******************************
*************************************************************************/

// Reconstrução do pacote após processamento
control MyDeparser(packet_out packet, in headers hdr) {
    apply {
        packet.emit(hdr.ethernet);      // Adiciona o cabeçalho Ethernet ao pacote
    }
}

/*************************************************************************
***********************  S W I T C H  *******************************
*************************************************************************/

V1Switch(
    MyParser(),
    MyVerifyChecksum(),
    MyIngress(),
    MyEgress(),
    MyComputeChecksum(),
    MyDeparser()
) main;

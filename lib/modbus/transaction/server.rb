# Copyright © 2016 Andy Rohr <andy.rohr@mindclue.ch>
# All rights reserved.


module Modbus
  module Transaction

    class Server < Base


      # Try to decode a response ADU from some received bytes and handle the ADU if decoding was successful.
      #
      # @param buffer [String] The bytes received from the network.
      # @param conn [Modbus::Connection::TCPServer] An EM connection object to work on.
      # @return [true, false] True, if there where enough bytes in the buffer and decoding was successful.
      #
      def self.recv_adu(buffer, conn)
        adu = Modbus::TCPADU.new

        if adu.decode :request, buffer, conn
          transaction = self.new conn
          transaction.handle_request adu
          return true
        else
          return false
        end
      end


      # Constructs a ADU using a PDU and send it asynchronously ly to the server.
      # The created ADU is stored internally and is matched to the response when the response is available.
      #
      # @param pdu [Modbus::PDU] The PDU to send.
      # @return [Modbus::TCPADU] The sent ADU.
      #
      def send_pdu(pdu)
        @response_adu = TCPADU.new pdu, @request_adu.transaction_ident
        @conn.send_data @response_adu.encode
        self
      end


      # Handles a received ADU and calls the relevant callback.
      # The corresponding request ADU is matched and cleaned up.
      #
      # @param adu [Modbus::ADU] The ADU to handle.
      #
      def handle_request(adu)
        @request_adu = adu

        transaction = TRANSACTIONS.find { |t| adu.pdu.is_a? t[:request] }
        fail IllegalFunction,     "Unknown PDU #{adu.pdu.inspect}" unless transaction
        fail ServerDeviceFailure, "Unexpected last sent PDU: #{@request_adu.pdu.inspect}" unless @request_adu.pdu.is_a? transaction[:request]

        pdu = send transaction[:handler]
        send_pdu pdu

      rescue ModbusError => error
        send_pdu PDU::Exception.create(adu.pdu.func_code, error)
      end


      def handle_read_coils
        read_bits :coils, PDU::ReadCoilsResponse
      end


      def handle_read_input_status
        read_bits :input_status, PDU::ReadInputStatusResponse
      end


      def read_bits(table, response_class)
        number         = address_to_number table, @request_adu.pdu.start_addr
        bit_values     = @conn.read_bits number, @request_adu.pdu.bit_count
        pdu            = response_class.new
        pdu.bit_values = bit_values
        pdu
      end


      def handle_read_input_registers
        read_registers :input_registers, PDU::ReadInputRegistersResponse
      end


      def handle_read_holding_registers
        read_registers :holding_registers, PDU::ReadHoldingRegistersResponse
      end


      def read_registers(table, response_class)
        number         = address_to_number table, @request_adu.pdu.start_addr
        reg_values     = @conn.read_registers number, @request_adu.pdu.reg_count
        pdu            = response_class.new
        pdu.reg_values = reg_values
        pdu
      end


      def handle_write_single_coil
        number         = address_to_number :coils, @request_adu.pdu.start_addr
        value          = @conn.write_bit number, @request_adu.pdu.value
        pdu            = PDU::WriteSingleCoilResponse.new
        pdu.start_addr = @request_adu.pdu.start_addr
        pdu.value      = value
        pdu
      end


      def handle_write_multiple_registers
        number         = address_to_number :holding_registers, @request_adu.pdu.start_addr
        reg_count      = @conn.write_registers number, @request_adu.pdu.reg_values
        pdu            = PDU::WriteMultipleRegistersResponse.new
        pdu.start_addr = @request_adu.pdu.start_addr
        pdu.reg_count  = reg_count
        pdu
      end


    end # Server

  end # Transaction
end # Modbus


